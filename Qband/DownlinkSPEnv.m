classdef DownlinkSPEnv < rl.env.MATLABEnvironment
    % DownlinkSPEnv - 下行调度预留的强化学习环境（修正版）
    % 动作空间压缩至16个，奖励基于使用效率，冲突检测使用 dl_slot_states

    properties
        Handle;
        CurrentSTAIdx = 1;
        MaxSlotsPerMS = 20;
        MaxPreConNum = 24;          % 全局最大预留时隙
        DecisionInterval = 200;     % 决策间隔（时隙）= 10ms

        StateHistory = [];
        ActionHistory = [];
        RewardHistory = [];

        Agents = {};                % 每个 STA 的独立 Agent
        SharedBuffer;              % 共享经验池
        ablationMode = 'full';% 可选值：
                          % 'full'          → 完整方法（推荐）
                          % 'no_fairness'   → 去掉公平性惩罚
                          % 'no_diversity'  → 去掉多样性奖励
                          % 'dqn'           → 只用基础 DQN
    end

    properties (Access = private)
        LastDecisionTime = 0;
        EpisodeStepCount = 0;
        MaxEpisodeSteps = 50;
        LastAction = [];
    end

    methods
        function this = DownlinkSPEnv(handles, sta_num)
            obsInfo = DownlinkSPEnv.createObservationInfo_static();
            actInfo = DownlinkSPEnv.createActionInfo_static();
            this = this@rl.env.MATLABEnvironment(obsInfo, actInfo);
            this.Handle = handles;
            this.CurrentSTAIdx = 1;
            this.Agents = cell(1, sta_num);
            this.SharedBuffer = rlReplayMemory(obsInfo, actInfo, 100000);
            for i = 1:sta_num
                this.Agents{i} = createD3QNAgent(this);
            end
        end

        % ------------------------------------------------------------
        % 核心 step 函数（符合 MATLAB 框架，仅两个输入参数）
        % ------------------------------------------------------------
        function [nextObs, reward, isDone, logged] = step(this, action)
            % 解析动作（cell 转数组）
            if iscell(action)
                action = action{1};
            end
            if length(action) < 3
                action = [0, 1, 0];
            end
            slot_num   = round(action(1));
            interval   = round(action(2));
            slot_index = round(action(3));

            % 动作验证
            if ~this.validateAction(slot_num, interval, slot_index)
                reward = -10;
                nextObs = this.getCurrentState();
                isDone = false;
                logged = struct('Valid', false);
                return;
            end

            sta_idx = this.CurrentSTAIdx;
            if sta_idx < 1 || sta_idx > numel(this.Handle.ap.stas_info)
                reward = -10;
                nextObs = this.getCurrentState();
                isDone = true;
                logged = struct('Error', 'Invalid STA');
                return;
            end

            % 获取当前 STA 的上周期数据
            s = this.Handle.ap.stas_info(sta_idx);
            last_used   = s.last_used_slots;       % 上一周期实际使用
            last_alloc  = s.last_allocated_slots;  % 上一周期分配数量

            % 应用新动作
            s.dl_resv_info.Slot_Num   = slot_num;
            s.dl_resv_info.Interval   = interval;
            s.dl_resv_info.Slot_Index = slot_index;
            s.dl_resv_info.Time_Index = 1;
            s.dl_resv_info.Cycles_Num = 10;
            s.control_flags_Down      = 3;   % 已由 RL 决策
            this.Handle.ap.stas_info(sta_idx) = s;

            % 计算奖励（基于上一周期的使用效率）
            reward = this.calculateReward(s, last_used, last_alloc);

            % 下一状态
            nextObs = this.getCurrentState();

            % Episode 终止判断
            this.EpisodeStepCount = this.EpisodeStepCount + 1;
            isDone = (this.EpisodeStepCount >= this.MaxEpisodeSteps) || (s.status == 0);

            logged = struct('STA', sta_idx, 'SlotNum', slot_num, ...
                            'Interval', interval, 'SlotIndex', slot_index, 'Reward', reward);
            this.LastAction = action;
        end

        % ------------------------------------------------------------
        % 环境重置（选择一个活动 STA 开始）
        % ------------------------------------------------------------
        function initObs = reset(this)
            this.EpisodeStepCount = 0;
            this.LastDecisionTime = 0;
            this.StateHistory = [];
            this.ActionHistory = [];
            this.RewardHistory = [];
            valid = find([this.Handle.ap.stas_info.status] == 1);
            if isempty(valid)
                this.CurrentSTAIdx = 1;
                initObs = zeros(10, 1);
            else
                this.CurrentSTAIdx = valid(randi(length(valid)));
                initObs = this.getCurrentState();
            end
        end

        % ------------------------------------------------------------
        % 状态观测（10维，含上一周期的使用效率）
        % ------------------------------------------------------------
        function obs = getCurrentState(this)
            if this.CurrentSTAIdx > numel(this.Handle.ap.stas_info) || this.CurrentSTAIdx < 1
                obs = zeros(10, 1);
                return;
            end
            s = this.Handle.ap.stas_info(this.CurrentSTAIdx);

            % 使用上一周期的数据计算分配成功率
            if s.last_allocated_slots > 0
                success_rate = min(s.last_used_slots / s.last_allocated_slots, 1.0);
            else
                success_rate = 0;
            end

            global_remaining = max(0, this.MaxPreConNum - this.getGlobalLoad());

            obs = [
                min(s.tid / 7, 1);
                min(sum([s.dl_tx_info.pkt_bytes]) / 1e6, 1);
                min(s.recent_rate_kbps / 1000, 1);
                min(this.getAverageDelay(s) / 100, 1);
                (s.dl_channel - 1) / 3;
                min(this.getGlobalLoad() / this.MaxPreConNum, 1);
                s.dl_resv_info.Slot_Num / 6;
                this.getCongestionFlag(s.dl_channel);
                success_rate;
                min(global_remaining / this.MaxPreConNum, 1)
            ];
        end

        % ------------------------------------------------------------
        % 动作验证（含基于 dl_slot_states 的冲突检测）
        % ------------------------------------------------------------
        function valid = validateAction(this, slot_num, interval, slot_index)
            valid = true;
            if slot_num < 0 || slot_num > 6        % 最大6个时隙
                valid = false; return;
            end
            if interval ~= 1                        % 固定间隔为1
                valid = false; return;
            end
            if slot_index < 0 || slot_index + slot_num - 1 > 19
                valid = false; return;
            end
            if slot_num > 0
                if this.checkSlotConflict(slot_num, slot_index)
                    valid = false;
                end
            end
        end

        % ------------------------------------------------------------
        % 冲突检测（直接读取 dl_slot_states）
        % ------------------------------------------------------------
        function conflict = checkSlotConflict(this, slot_num, slot_index)
            conflict = false;
            sta = this.Handle.ap.stas_info(this.CurrentSTAIdx);
            channel = sta.dl_channel;
            states = this.Handle.ap.dl_slot_states{channel};
            for i = 0:slot_num-1
                idx = slot_index + i + 1;   % 1-based
                if idx > numel(states) || states(idx) ~= 265   % 265 = NOT_DEFINED
                    conflict = true;
                    return;
                end
            end
        end

        % ------------------------------------------------------------
        % 奖励函数（基于使用效率，包含公平性、时延、负载）
        % ------------------------------------------------------------
        function reward = calculateReward(this, s, last_used, last_alloc)      
            mode = this.ablationMode;   % 获取当前消融模式
        
            % ====================== 1. 使用率奖励 ======================
            if last_alloc > 0
                usage_rate = min(last_used / last_alloc, 1.0);
                base = 25 + 35 * usage_rate;
            else
                has_data = sum([s.dl_tx_info.pkt_bytes]) > 300;
                if has_data
                    base = -8;
                else
                    base = 6;
                end
            end
        
            % ====================== 2. 全局负载奖励 ======================
            global_load = this.getGlobalLoad() / this.MaxPreConNum;
            if global_load < 0.35
                load_reward = global_load * 55;
            elseif global_load < 0.65
                load_reward = 14 + (global_load - 0.35) * 85;
            else
                load_reward = 39 + (global_load - 0.65) * 55;
            end
        
            % ====================== 3. 单 STA 时延奖励 ======================
            avg_delay = this.getAverageDelay(s);
            if avg_delay <= 12
                delay_reward = 18;
            elseif avg_delay <= 30
                delay_reward = 18 - 0.9 * (avg_delay - 12);
            else
                delay_reward = -15 - 1.0 * (avg_delay - 30);
            end
        
            % ====================== 4. 最坏情况惩罚 ======================
            max_delay = this.getMaxDelay();
            if max_delay > 25
                worst_penalty = -6.5 * (max_delay - 25);
            else
                worst_penalty = 0;
            end
        
            % ====================== 5. 公平性惩罚（修复版）======================
            if strcmp(mode, 'no_fairness')
                fairness_penalty = 0;
            else
                hungry_count = 0;
                delays = [];
                for i = 1:numel(this.Handle.ap.stas_info)
                    if this.Handle.ap.stas_info(i).status == 1
                        d = this.getAverageDelay(this.Handle.ap.stas_info(i));
                        delays(end+1) = d;
                        % 判断是否"饥饿"：缓冲区大 或 时延高
                        if sum([this.Handle.ap.stas_info(i).dl_tx_info.pkt_bytes]) > 500 || d > 25
                            hungry_count = hungry_count + 1;
                        end
                    end
                end
                delay_var = var(delays);
                if isempty(delay_var) || isnan(delay_var)
                    delay_var = 0;
                end
        
                fairness_penalty = -9 * hungry_count - 4 * delay_var;
            end
        
            % ====================== 6. 多样性奖励（根据模式动态调整）======================
            if strcmp(mode, 'no_diversity')
                diversity = 0;
            else
                new_act = [s.dl_resv_info.Slot_Num, 1, s.dl_resv_info.Slot_Index];
                diversity = ~isequal(round(new_act), round(this.LastAction)) * 2 - 0.5;
            end
        
            % ====================== 最终奖励 ======================
            reward = base + load_reward + delay_reward + worst_penalty + fairness_penalty + diversity;
            reward = max(min(reward, 145), -90);
        end
        % ------------------------------------------------------------
        % 辅助函数（保持不变）
        % ------------------------------------------------------------
        function avg = getAverageDelay(~, sta_info)
            delays = [sta_info.dl_tx_info.tot_tx_delay] ./ ...
                     max(1, [sta_info.dl_tx_info.tot_tx_bagnum]);
            avg = mean(delays(delays > 0));
            if isempty(avg); avg = 0; end
        end

        function load = getGlobalLoad(this)
            load = 0;
            for i = 1:numel(this.Handle.ap.stas_info)
                s = this.Handle.ap.stas_info(i);
                if s.status == 1 && s.dl_resv_info.Slot_Num > 0
                    load = load + s.dl_resv_info.Slot_Num;
                end
            end
        end

        function c = getCongestionFlag(this, channel)
            if channel <= numel(this.Handle.ap.dl_channel_info)
                c = double(numel(this.Handle.ap.dl_channel_info{channel}) > 3);
            else
                c = 0;
            end
        end

        function max_delay = getMaxDelay(this)
            max_delay = 0;
            for i = 1:numel(this.Handle.ap.stas_info)
                if this.Handle.ap.stas_info(i).status == 1
                    d = this.getAverageDelay(this.Handle.ap.stas_info(i));
                    if d > max_delay; max_delay = d; end
                end
            end
        end

        function applyBaselineAction(this, method)
        sta_idx = this.CurrentSTAIdx;
        if sta_idx < 1 || sta_idx > numel(this.Handle.ap.stas_info)
            return;
        end
        
        s = this.Handle.ap.stas_info(sta_idx);
        
        switch lower(method)
            case 'fixed'
                % 固定预留（最简单传统方法）
                s.dl_resv_info.Slot_Num = 4;
                s.dl_resv_info.Interval = 1;
                s.dl_resv_info.Slot_Index = 0;
                
            case 'roundrobin'
                % 轮询调度
                persistent rr_counter;
                if isempty(rr_counter)
                    rr_counter = 0;
                end
                rr_counter = mod(rr_counter + 1, 3);
                s.dl_resv_info.Slot_Num = 2 + rr_counter;
                s.dl_resv_info.Interval = 1;
                s.dl_resv_info.Slot_Index = mod(sta_idx * 4, 16);
                
            case 'greedy'
                % 贪心策略（基于时延和缓冲区）
                avg_delay = this.getAverageDelay(s);
                buf_size = sum([s.dl_tx_info.pkt_bytes]);
                if avg_delay > 35 || buf_size > 800
                    s.dl_resv_info.Slot_Num = 5;
                elseif avg_delay > 20 || buf_size > 400
                    s.dl_resv_info.Slot_Num = 3;
                else
                    s.dl_resv_info.Slot_Num = 1;
                end
                s.dl_resv_info.Interval = 1;
                s.dl_resv_info.Slot_Index = 0;
                
            case 'random'
                % 随机分配（最差 baseline）
                s.dl_resv_info.Slot_Num = randi([0, 5]);
                s.dl_resv_info.Interval = 1;
                s.dl_resv_info.Slot_Index = randi([0, 12]);
                
            case 'threshold'
                % 简单阈值策略
                buf_size = sum([s.dl_tx_info.pkt_bytes]);
                if buf_size > 600
                    s.dl_resv_info.Slot_Num = 4;
                else
                    s.dl_resv_info.Slot_Num = 1;
                end
                s.dl_resv_info.Interval = 1;
                s.dl_resv_info.Slot_Index = 0;
                
            otherwise
                % 默认不预留
                s.dl_resv_info.Slot_Num = 0;
                fprintf('未知的 Baseline 方法: %s\n', method);
        end
        
        % 统一设置
        s.dl_resv_info.Time_Index = 1;
        s.dl_resv_info.Cycles_Num = 10;
        s.control_flags_Down = 3;
        
        this.Handle.ap.stas_info(sta_idx) = s;
    end
    end

    methods (Static)

        function obsInfo = createObservationInfo_static()
            obsInfo = rlNumericSpec([10 1]);
            obsInfo.Name = 'Downlink State';
            obsInfo.LowerLimit = 0; 
            obsInfo.UpperLimit = 1;
        end
        
        function actInfo = createActionInfo_static()
            % 动作空间包含 slot_num=0（关键修复）
            actions = {};
            slot_nums = [0, 2, 4, 6];      % ← 已包含 0
            slot_indices = 0:4:12;         % 0,4,8,12
            
            for sn = slot_nums
                for si = slot_indices
                    if sn == 0 || (si + sn - 1 <= 19)
                        actions{end+1} = [sn, 1, si];
                    end
                end
            end
            
            actInfo = rlFiniteSetSpec(actions);
            actInfo.Name = 'Downlink Pre-reservation Action';
            fprintf('动作空间大小 = %d（已包含 slot_num=0）\n', length(actions));
        end       
    end
end

