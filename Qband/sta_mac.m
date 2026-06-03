classdef sta_mac <handle
    properties (Access = public)
        slot_idx        %当前时隙号
        dl_slot_states  %下行信道beacon周期内的每个时隙的状态
        ul_slot_states  %上行信道beacon周期内的每个时隙的状态
        uid             %用户id信息
        status          %STA状态
        mac_address     %用户mac地址
        stas_info       %相关联的sta的信息
        tx_queue        %发送缓存队列
        control_queue   %控制帧发送缓存队列
        retry_queue     %重传队列
        backup_queue    %发送备份队列
        ps_info         %省电信息
        ul_resv_info    %上行信道预留信息
        Reqflag         %上行信道预留标志
        dl_resv_info    %下行信道预留信息
        Reqflag_Upchannel %极低时延上行信道预留标志
        Reqflag_Downchannel %极低时延下行信道预留标志
        backoff_info    %随机接入退避信息
        mcs_update_info  %MCS等级更新信息
        mcs_flag         %MCS等级可用信息
        dl_rx_delay      %下行链路的接收时延
        dl_rx_bagnum     %下行链路提交包总数
        ul_tx_delay      %上行链路发送时延
        ul_tx_bagnum     %上行链路发送包总数
        pkt_bytes        %每个发送缓存队列的包字节数
        tid              %sta发送的数据业务类型
        seq              %当前待传帧序号
        tx_rate          %发送速率
        BSR_state        %表明当前1ms内该STA是否已上报BSR帧
        offline_req      %表明当前STA是否发下线请求
        IFoffline
        dl_channel
        ul_channel
%         throughput       %吞吐量统计
        %%%%%%%%%%ARQ相关信息%%%%%%%%%%%%%%%%
        lsn             %接收整序队列的下沿序号
        rx_array        %接收整序队列
        fsn             %bitmap起始序号
        ack             %确认位图
        transID         %控制帧的ID序号
        maxoffset       %当前1ms内最后收到的帧序号
        msn             %bitmap偏移量最大序号

        % ============ EDCA机制新增属性 ============
        edca_ac_params      % EDCA访问类别参数
        edca_state          % EDCA状态变量
        edca_queues         % 按AC分类的队列
        edca_backoff        % EDCA退避状态
        qos_enabled         % QoS可用标志
        edca_mcs_strategy   % EDCA MCS选择策略

    end 
    methods
        function obj = sta_mac()
            obj.uid = -1;
            obj.status = 0; 
            obj.dl_slot_states = ones(1,200);
%           obj.dl_slot_states(:) = 265;
            obj.dl_rx_delay = zeros(1,8);  
            obj.dl_rx_bagnum = zeros(1,8);
            obj.ul_tx_delay = zeros(1,8);
            obj.ul_tx_bagnum = zeros(1,8);
            obj.pkt_bytes = zeros(1,8);
            obj.tid = 0;
            obj.seq = zeros(1,8);
            obj.tx_rate = 10000000;  %每ms产万个包
            obj.BSR_state = 0;
            obj.ul_resv_info = struct('Time_Index',0,'Interval',0,'Slot_Index',0,'Slot_Num',0,'Cycles_Num',0,'control_flags',false);
            obj.dl_resv_info = struct('Time_Index',0,'Interval',0,'Slot_Index',0,'Slot_Num',0,'Cycles_Num',0,'control_flags',false);
            obj.Reqflag = false;
            obj.Reqflag_Upchannel = 0;    % 0表示不发送请求，1表示发送请求，2表示允许低时延下行通信
            obj.Reqflag_Downchannel = 0;    % 0表示不发送请求，1表示发送请求，2表示允许低时延上行通信
            obj.offline_req = 0;
            obj.IFoffline = 0;
            obj.dl_channel = 1; %考虑到接入时需要进行交互，STA初始上下行信道索引均置为1，收到关联响应之后更改
            obj.ul_channel = 1; 
            %0213 test zhao
            obj.dl_slot_states(:) = 261;
            
            for idx = 1 : 20 : 200
                obj.dl_slot_states(idx) = 261;          %261为RX
                obj.dl_slot_states(idx+18) = 261;
                obj.dl_slot_states(idx+19) = 261;
            end
            obj.tx_queue = myQueue();
            obj.backup_queue = myQueue(); 
            obj.retry_queue = myQueue();
            for n = 1 : 8
                obj.tx_queue(n) = myQueue(); 
                obj.backup_queue(n) = myQueue(); 
                obj.retry_queue(n) = myQueue(); 
            end
            obj.ul_slot_states = ones(1,200);
            obj.ul_slot_states(:) = 265;
            for idx = 1 : 100 : 200
                obj.ul_slot_states(idx) = 263;      %263代表random access
                obj.ul_slot_states(idx + 1) = 263;
            end
            obj.control_queue = myQueue();
            %%%%退避参数%%%%%%
            obj.backoff_info = struct('loop', 0, 'val', 0);    %0表示未开始backoff   n代表正在第n轮backoff
            obj.mcs_update_info = struct('mcs_val',1,'failed_num',0,'count',0,'start_time_tick',0,'restricted_mcs',9,'time_lock',-1,'throughput',0); %最大MCS等级可用宏来表示
            for i = 1 : 8
                obj.mcs_update_info(i) = struct('mcs_val',3,'failed_num',0,'count',0,'start_time_tick',0,'restricted_mcs',9,'time_lock',-1,'throughput',0);
            end
            %%%%ARQ反馈相关%%%%
            obj.lsn = zeros(8,1);
            obj.rx_array = repmat(struct('frame','','time_stamp',0), 8, 2^16);
%             obj.rx_array = repmat([], 1, 2^16);
            obj.fsn = repmat(-1, 1, 8);
            obj.msn = repmat(-1, 1, 8);
            obj.ack = {};  

            %%%%EDCA机制初始化%%%%%%%% 
            obj = init_edca_mechanism(obj);
        end


        function obj = init_edca_mechanism(obj)
            obj.qos_enabled = true;    
            ac_config = struct();
            
            ac_config.AC_VO = struct('AIFSN', 2, 'CWmin', 3, 'CWmax', 7, 'TXOP', 60, 'priority', 1, 'mcs_preference', 'reliability' );
            ac_config.AC_VI = struct('AIFSN', 2, 'CWmin', 7, 'CWmax', 15, 'TXOP', 120, 'priority', 2, 'mcs_preference', 'balance' );
            ac_config.AC_BE = struct('AIFSN', 3, 'CWmin', 15, 'CWmax', 1023, 'TXOP', 0, 'priority', 3,'mcs_preference', 'throughput' );
            ac_config.AC_BK = struct('AIFSN', 7, 'CWmin', 15, 'CWmax', 1023, 'TXOP', 0, 'priority', 4, 'mcs_preference', 'throughput' );
            
            obj.edca_ac_params = ac_config;
            
            obj.edca_state = struct('channel_busy', false, 'nav_end_time', 0, 'last_busy_time', 0, 'current_txop', 0, 'txop_start_time', 0 );
           
            obj.edca_queues = struct();
            ac_names = {'AC_VO', 'AC_VI', 'AC_BE', 'AC_BK'};
            for i = 1:length(ac_names)
                obj.edca_queues.(ac_names{i}) = myQueue();
            end
            
            % 初始化退避状态
            obj.edca_backoff = struct();
            for i = 1:length(ac_names)
                obj.edca_backoff.(ac_names{i}) = struct('backoff_counter', 0, 'current_cw', ac_config.(ac_names{i}).CWmin, 'retry_count', 0, 'backoff_active', false );
            end
            
            % 初始化EDCA MCS选择策略
            obj.edca_mcs_strategy = struct('reliability_bias', -1, 'throughput_bias', 1, 'balance_bias', 0, 'min_mcs', 1, 'max_mcs', 8, 'recent_success_rate', 0.95, 'channel_quality_threshold', 0.8 );
        end
        
        %%%%%%%%EDCA核心方法%%%%%%%%%
        
        function ac_index = map_tid_to_ac(obj,tid)
            switch tid
                case {6, 7}
                    ac_index = 1; % AC_VO
                case {4, 5}
                    ac_index = 2; % AC_VI
                case {0, 3}
                    ac_index = 3; % AC_BE
                case {1, 2}
                    ac_index = 4; % AC_BK
                otherwise
                    ac_index = 3; % 默认AC_BE
            end
        end
        
        function ac_name = get_ac_name(obj,ac_index)
            ac_names = {'AC_VO', 'AC_VI', 'AC_BE', 'AC_BK'};
            if ac_index >= 1 && ac_index <= length(ac_names)
                ac_name = ac_names{ac_index};
            else
                ac_name = 'AC_BE';
            end
        end
        
        function [access_granted, ac_index , need_retry] = edca_channel_access(obj, current_time)       
            need_retry = false;
            
            if obj.edca_state.channel_busy || current_time < obj.edca_state.nav_end_time
                access_granted = false;
                ac_index = 0;
        
                % 检查是否需要触发重传超时
                for ac_idx = 1:4
                    ac_name = obj.get_ac_name(ac_idx);
                    if ~obj.edca_queues.(ac_name).isempty() && obj.check_retransmission_timeout(ac_name, current_time)
                        need_retry = true;
                    end
                end
                return;
             end
             for ac_idx = 1:4
                ac_name = obj.get_ac_name(ac_idx);
                
                % 检查队列是否非空且满足AIFS时间
                if ~obj.edca_queues.(ac_name).isempty() && obj.check_aifs_time(ac_name, current_time)
                    
                    % 检查退避计数器
                    if obj.edca_backoff.(ac_name).backoff_counter == 0
                        access_granted = true;
                        ac_index = ac_idx;
                        return;
                    end
                end
            end
        
            access_granted = false;
            ac_index = 0;
        end
        
        function satisfied = check_aifs_time(obj, ac_name, current_time)
            aifsn = obj.edca_ac_params.(ac_name).AIFSN;
            aifs_time = aifsn; 
            
            satisfied = (current_time - obj.edca_state.last_busy_time) >= aifs_time;
        end
        
        function obj = start_edca_backoff(obj, ac_name)
            backoff_info = obj.edca_backoff.(ac_name);
            ac_params = obj.edca_ac_params.(ac_name);
            
            if ~backoff_info.backoff_active
                % 选择新的退避计数器
                if floor(backoff_info.current_cw) ~= backoff_info.current_cw 
                    backoff_info.current_cw = floor(backoff_info.current_cw);
                end
                backoff_info.backoff_counter = randi([backoff_info.current_cw]);
                backoff_info.retry_count = backoff_info.retry_count + 1;
                backoff_info.backoff_active = true;
                
                % 更新竞争窗口 (指数退避)
                if backoff_info.retry_count > 0
                    new_cw = min(2 * (backoff_info.current_cw + 1) - 1, ac_params.CWmax);
                    backoff_info.current_cw = new_cw;
                end
                
                obj.edca_backoff.(ac_name) = backoff_info;
            end
        end
        
        function obj = update_edca_backoff(obj, ac_name)
            if obj.edca_backoff.(ac_name).backoff_active && obj.edca_backoff.(ac_name).backoff_counter > 0
                obj.edca_backoff.(ac_name).backoff_counter = obj.edca_backoff.(ac_name).backoff_counter - 1;
                
                if obj.edca_backoff.(ac_name).backoff_counter == 0
                    obj.edca_backoff.(ac_name).backoff_active = false;
                end
            end
        end
        
        function obj = reset_edca_backoff(obj, ac_name)
            % 重置退避参数 (成功传输后)
            ac_params = obj.edca_ac_params.(ac_name);
            
            obj.edca_backoff.(ac_name) = struct('backoff_counter', 0, 'current_cw', ac_params.CWmin, 'retry_count', 0, 'backoff_active', false );
        end
        
        function obj = enqueue_edca_frame(obj, frame, tid, time_stamp)
            ac_index = obj.map_tid_to_ac(tid);
            ac_name = obj.get_ac_name(ac_index);
            
            frame_info = struct('frame', frame, 'time_stamp', time_stamp, 'tid', tid, 'ac_index', ac_index );
            
            obj.edca_queues.(ac_name).push(frame_info);
            
            % 如果是新帧且退避未进行，开始退避
            if ~obj.edca_backoff.(ac_name).backoff_active
                obj = obj.start_edca_backoff(ac_name);
            end
        end
        
        function [frame_info, ac_name] = dequeue_edca_frame(obj, ac_index)
            ac_name = obj.get_ac_name(ac_index);
            
            if ~obj.edca_queues.(ac_name).isempty()
                frame_info = obj.edca_queues.(ac_name).pop();
            else
                frame_info = [];
            end
        end
        
        function queue_length = get_edca_queue_length(obj, ac_index)
            ac_name = obj.get_ac_name(ac_index);
            queue_length = obj.edca_queues.(ac_name).getLength();
        end
        
        function obj = update_channel_state(obj, is_busy, current_time)
            obj.edca_state.channel_busy = is_busy;
            
            if is_busy
                obj.edca_state.last_busy_time = current_time;
            end
        end
        
        function mcs_val = get_mcs_for_edca(obj, ac_index, varargin)
            p = inputParser;
            addOptional(p, 'channel_quality', 0.9, @(x) x>=0 && x<=1);
            addOptional(p, 'packet_size', 1000, @isnumeric);
            parse(p, varargin{:});

            channel_quality = p.Results.channel_quality;
            % packet_size = p.Results.packet_size;

            ac_name = obj.get_ac_name(ac_index);
            ac_params = obj.edca_ac_params.(ac_name);

            % 基础MCS选择（基于TID 0的MCS）
            base_mcs = obj.mcs_update_info(1).mcs_val;

            % 根据AC的MCS偏好进行调整
            switch ac_params.mcs_preference
                case 'reliability'   
                    mcs_val = base_mcs - 1;
                case 'throughput'
                    mcs_val = base_mcs + 1;
                case 'balance'
                    mcs_val = base_mcs;
                otherwise
                    mcs_val = base_mcs;
            end

            if channel_quality < 0.7
                mcs_val = mcs_val - 1;
            elseif channel_quality > 0.9
                mcs_val = mcs_val + 1;
            end

            mcs_val = max(1, min(8, mcs_val));
        end
        
        function quality = estimate_channel_quality(obj, varargin)
            p = inputParser;
            addParameter(p, 'window_size', 100, @(x) x>0 && x<=1000);
            addParameter(p, 'use_snr', false, @islogical);
            addParameter(p, 'channel_id', obj.ul_channel, @(x) x>0);
            parse(p, varargin{:});
            
            window_size = p.Results.window_size;
            use_snr = p.Results.use_snr;
            channel_id = p.Results.channel_id;
            
            % 基于历史传输成功率的估算
            quality_success = estimate_by_success_rate(obj, window_size);
              
            % 如果有SNR信息，使用SNR估算
            if use_snr
                quality_snr = estimate_by_snr(channel_id);
            else
                quality_snr = 0.5; % 默认值
            end
            
            % 基于最近传输延迟的估算
            quality_delay = estimate_by_delay(obj);
            
            % 加权融合各个质量指标
            weights = [0.5, 0.3, 0.2]; 
            qualities = [quality_success, quality_snr, quality_delay];
            
            quality = sum(weights .* qualities);
           
            quality = max(0.05, min(0.95, quality));
        end
        
        function quality = estimate_by_success_rate(obj, window_size)
            total_frames = sum(obj.ul_tx_bagnum);
            
            if total_frames == 0
                quality = 0.8; % 初始假设信道较好
                return;
            end
            
            % 计算近期成功率（考虑窗口大小）
            recent_frames = min(window_size, total_frames);
            if total_frames > window_size
                % 估算近期失败率（简化处理）
                total_failures = sum([obj.mcs_update_info.failed_num]);
                recent_failures = total_failures * (recent_frames / total_frames);
            else
                recent_failures = sum([obj.mcs_update_info.failed_num]);
            end
            
            success_rate = (recent_frames - recent_failures) / recent_frames;
            
            % 对成功率进行非线性映射，更好反映信道质量
            if success_rate > 0.9
                quality = 0.9 + (success_rate - 0.9) * 0.5; 
            elseif success_rate > 0.7
                quality = 0.7 + (success_rate - 0.7) * 1.0; 
            else
                quality = success_rate * 0.7 / 0.7; 
            end
        end

        function quality = estimate_by_snr(obj,channel_id) 
            try
                % 假设可以从某个地方获取SNR信息
                snr_value = get_current_snr(channel_id); % 需要实现这个函数
                
                % 将SNR映射到质量值
                if snr_value > 25
                    quality = 0.9;
                elseif snr_value > 15
                    quality = 0.7 + (snr_value - 15) * 0.02;
                elseif snr_value > 5
                    quality = 0.3 + (snr_value - 5) * 0.04;
                else
                    quality = snr_value * 0.06;
                end
            catch
                quality = 0.5; % 如果SNR不可用，返回默认值
            end
        end
        
        function quality = estimate_by_delay(obj)
            if isempty(obj.ul_tx_delay) || all(obj.ul_tx_delay == 0)
                quality = 0.5;
                return;
            end
            
            % 计算平均传输延迟
            valid_delays = obj.ul_tx_delay(obj.ul_tx_delay > 0);
            if isempty(valid_delays)
                quality = 0.5;
                return;
            end
            
            avg_delay = mean(valid_delays);
            
            % 将延迟映射到质量值（延迟越小质量越高）
            if avg_delay < 1 % 1ms
                quality = 0.9;
            elseif avg_delay < 5 % 5ms
                quality = 0.9 - (avg_delay - 1) * 0.1;
            elseif avg_delay < 10 % 10ms
                quality = 0.6 - (avg_delay - 5) * 0.06;
            else
                quality = max(0.1, 0.3 - (avg_delay - 10) * 0.02);
            end
        end
        
        function snr = get_current_snr(obj,channel_id)
            persistent snr_history;
            if isempty(snr_history)
                snr_history = containers.Map('KeyType', 'double', 'ValueType', 'double');
            end
            
            if isKey(snr_history, channel_id)
                snr = snr_history(channel_id);
            else
                % 默认SNR值，实际应该从物理层获取
                snr = 20 + randn(1) * 2; 
                snr_history(channel_id) = snr;
            end
        end
        
         function obj = handle_edca_retransmission(obj, ac_name, frame_info, varargin)
            p = inputParser;
            addParameter(p, 'max_retries', 7, @isnumeric);
            addParameter(p, 'backoff_strategy', 'exponential', @ischar);
            parse(p, varargin{:});
            
            max_retries = p.Results.max_retries;
            backoff_strategy = p.Results.backoff_strategy;
            
            % 获取当前AC的重传状态
            backoff_info = obj.edca_backoff.(ac_name);
            
            if backoff_info.retry_count >= max_retries
                fprintf('STA %d %s 帧达到最大重传次数(%d)，丢弃帧\n', obj.uid, ac_name, max_retries);
                obj = obj.update_retransmission_stats(ac_name, 'dropped');
                return;
            end
            
            % 根据退避策略更新竞争窗口
            switch backoff_strategy
                case 'exponential'
                    new_cw = min(2 * (backoff_info.current_cw + 1) - 1,  obj.edca_ac_params.(ac_name).CWmax);
                case 'linear'
                    new_cw = min(backoff_info.current_cw + obj.edca_ac_params.(ac_name).CWmin,  obj.edca_ac_params.(ac_name).CWmax);
                case 'aggressive'
                    new_cw = obj.edca_ac_params.(ac_name).CWmin;
                otherwise
                    new_cw = min(2 * (backoff_info.current_cw + 1) - 1,  obj.edca_ac_params.(ac_name).CWmax);
            end
            
            backoff_info.current_cw = new_cw;
            backoff_info.retry_count = backoff_info.retry_count + 1;
            backoff_info.backoff_counter = randi([new_cw]);
            backoff_info.backoff_active = true;
            
            obj.edca_backoff.(ac_name) = backoff_info;
            
            % 重新入队进行重传
            frame_info.retry_count = backoff_info.retry_count;
            obj.edca_queues.(ac_name).push(frame_info);
            
            fprintf('STA %d %s 第%d次重传，CW=%d，退避计数=%d\n',  obj.uid, ac_name, backoff_info.retry_count, new_cw,  backoff_info.backoff_counter);
            
            obj = obj.update_retransmission_stats(ac_name, 'retry');
        end
        
        function obj = update_retransmission_stats(obj, ac_name, action)
            % 更新重传统计信息
            if ~isfield(obj.edca_state, 'retransmission_stats')
                obj.edca_state.retransmission_stats = struct();
            end
            
            if ~isfield(obj.edca_state.retransmission_stats, ac_name)
                obj.edca_state.retransmission_stats.(ac_name) = struct('retry_count', 0, 'success_count', 0, 'drop_count', 0);
            end
            
            stats = obj.edca_state.retransmission_stats.(ac_name);
            
            switch action
                case 'retry'
                    stats.retry_count = stats.retry_count + 1;
                case 'success'
                    stats.success_count = stats.success_count + 1;
                case 'dropped'
                    stats.drop_count = stats.drop_count + 1;
            end
            
            obj.edca_state.retransmission_stats.(ac_name) = stats;
        end
        
        function timeout = check_retransmission_timeout(obj, ac_name, current_time)
            % 检查重传超时
            timeout = false;
            
            if ~isfield(obj.edca_state, 'last_tx_time')
                return;
            end
            
            if isfield(obj.edca_state.last_tx_time, ac_name)
                last_tx = obj.edca_state.last_tx_time.(ac_name);
                timeout_interval = obj.get_retransmission_timeout(ac_name);
                
                if (current_time - last_tx) > timeout_interval
                    timeout = true;
                end
            end
        end
        
        function timeout = get_retransmission_timeout(obj,ac_name)
            % 获取重传超时时间（基于AC优先级）
            switch ac_name
                case 'AC_VO'
                    timeout = 4;  
                case 'AC_VI'
                    timeout = 8;  
                case 'AC_BE'
                    timeout = 16; 
                case 'AC_BK'
                    timeout = 32; 
                otherwise
                    timeout = 16;
            end
        end
        
    end
end