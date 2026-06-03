function results = startSimulation(simulation_mode, ablationMode, baseline_method, sta_num, simulation_time)
    if nargin < 1, simulation_mode = 'RL'; end
    if nargin < 2, ablationMode = 'full'; end
    if nargin < 3, baseline_method = ''; end
    if nargin < 4, sta_num = 4; end
    if nargin < 5, simulation_time = 2; end
    close all
    load const_value;
    
    % ==================== 处理 DQN 模式 ====================
    if strcmpi(simulation_mode, 'DQN')
        simulation_mode = 'RL';
        ablationMode = 'full';
        use_d3qn = false;                    % 使用普通 DQN
    else
        use_d3qn = true;
    end
    % if ~exist('training_samples', 'var') || isempty(training_samples)
    %     training_samples = [];
    %     sample_count = 0;
    % end
    % ema_usage = 0;   % 初始化
    % % 初始化存储EDCA统计数据的数组
    % edca_time_points = [];  % 时间点（时隙）
    
    % 整体统计
    % overall_stats = struct();
    % overall_stats.time_points = [];
    % overall_stats.avg_retry_rates = struct('AC_VO', [], 'AC_VI', [], 'AC_BE', [], 'AC_BK', []);
    % % overall_stats.channel_utilization = [];
    
    fid = fopen('delay.txt','a');
    
    dl_rate = 100;
    ul_rate = 10;
    aver_dl_tx_delay = []; %平均下行发送时延
    aver_dl_rx_delay = []; %平均下行接收时延
    aver_ul_tx_delay = []; %平均上行发送时延
    aver_ul_rx_delay = []; %平均上行接收时延
    time = cell(sta_num,1); %单位为秒
    time_dl = cell(sta_num,1); %单位为秒
    stas_ul_delay = cell(sta_num,1);
    stas_dl_delay = cell(sta_num,1);
    stas_dl_throughput = cell(sta_num,1);
    handle.ap = ap_mac();
    handle.ap.mac_address = 'FDDa00000000';
    handle.stas = cell(1, sta_num);
    handle.mcs_table = mcs_table();
    fc = 42e9;
    ul_nbits = 1000;  %目前上行数据包长均大致为2000
    dl_nbits = 1000; 
    mcs_idx = 8;
    dist = 5;
    mcs_ss = handle.mcs_table.table_elem;
    dl_channel_width = 540;  
    ul_channel_width = 540;
    dl_channel_width_ell = 540;  
    ul_channel_width_ell = 540;
    dl_powerLevel = 12;
    ul_powerLevel = 12;
    txGain = 10;
    dl_snr = caculate_snr(dl_channel_width, dist, fc, dl_powerLevel, txGain,1);
    ul_snr = caculate_snr(ul_channel_width, dist, fc, ul_powerLevel, txGain,1);
    dl_snr_ell = caculate_snr(dl_channel_width_ell, dist, fc, dl_powerLevel, txGain,1);
    ul_snr_ell = caculate_snr(ul_channel_width_ell, dist, fc, ul_powerLevel, txGain,1);
    dl_csr = zeros(1,8);
    ul_csr = zeros(1,8);
    for mcs_idx = 1 : 8
        dl_csr(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),dl_snr, dl_nbits);
        ul_csr(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),ul_snr, ul_nbits);
        dl_csr_ell(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),dl_snr_ell, dl_nbits);
        ul_csr_ell(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),ul_snr_ell, ul_nbits);   
    end
    handle.dl_csr = dl_csr;  %下行发送成功率表
    handle.ul_csr = ul_csr;  %上行发送成功率表
    % handle.dl_csr = [1,1,1,1,1,1,1,1];  %下行发送成功率表
    % handle.ul_csr = [1,1,1,1,1,1,1,1];  %上行发送成功率表
    handle.dl_csr_ell = dl_csr_ell;  %极低时延信道下行发送成功率表
    handle.ul_csr_ell = ul_csr_ell;  %极低时延信道上行发送成功率表
    % handle.dl_csr_ell = [1,1,1,1,1,1,1,1];  %极低时延信道下行发送成功率表
    % handle.ul_csr_ell = [1,1,1,1,1,1,1,1];  %极低时延信道上行发送成功率表
    
    aver_dl_tx = [];
    aver_dl_rx = [];
    aver_ul_tx = [];
    aver_ul_rx = [];
    for j = 1 : sta_num
        handle.stas{j} = sta_mac();
        %mac地址目前采用qband +　序号作为后缀的表示
        dec_address = comm.internal.utilities.de2biBase2LeftMSB(double(j), 48);
        hex_address = comm.internal.utilities.bi2deLeftMSB(double(reshape(dec_address, 8, [])'), 2);
        str_address = reshape(dec2hex(hex_address,2)', 1, []);
        mac_address = ['FDD',str_address(4:12)];
        handle.stas{j}.mac_address = mac_address;
    end
    
    %% ==================== 数据收集初始化 ====================
    usage_rate_history = [];      % 记录每次决策的使用率
    delay_history = [];           % 记录所有数据包的时延
    sta_delay_sum = zeros(1, sta_num);   % 每个 STA 的总时延
    sta_pkt_count = zeros(1, sta_num);   % 每个 STA 的数据包数量
    reward_per_sta = cell(1, sta_num);        % 每个 STA 一个独立的 reward 历史
    for i = 1:sta_num
        reward_per_sta{i} = [];
    end

    %%%%测试上行时隙预留%%%%
    handle.stas{2}.tid = 5;  
    handle.stas{2}.Reqflag = false;
    %%%%测试下行时隙预留%%%%
    flag = false;
    %%%%%测试低时延信道%%%%%
    handle.stas{1}.Reqflag_Downchannel = 1;
    handle.stas{1}.Reqflag_Upchannel = 1;
    %%%%%普通信道信息%%%%%%
    handle.dl_channel = {PhyChannel(540),PhyChannel(540),PhyChannel(540),PhyChannel(540)};
    handle.ul_channel = {PhyChannel(540),PhyChannel(540),PhyChannel(540),PhyChannel(540)};
    %%%%极低时延信道信息%%%%
    handle.dl_channel_ell = PhyChannel(540);
    handle.ul_channel_ell = PhyChannel(540);
    %%%%%%%%%%%%%%%%%%%%%%
    handle.ticks = simulation_time * 1000 * 20;
    handle.timeout_process(1).aid = 0;
    handle.timeout_process(1).mac_addr = '000000000000';
    handle.timeout_process(1).end_tick = handle.ticks+1;
    handle.timeout_process(1).fun_code = 0;
    handle.timeout_process(1).input = {};
    ulchannel_num  = cell(1,16);
    %%%%%初始化连接状态%%%%%
    for j = 1 : sta_num
        handle.stas{j}.status = 0;
    end
    % ==================== 数据记录初始化 ====================
    reward_history = [];           % RL 平均奖励历史
    action_stats = zeros(1, 100);   % 动作分布统计（假设你优化后是36个动作）
    precon_usage = [];             % 每10ms全局预留时隙使用率
    % channel_util = [];             % 信道利用率
    % avg_delay_history = [];        % 平均时延历史
    
    % state_data = struct();
    precon_sent = 0;          % AP 发送 PreCon_DownReq 次数
    precon_received = 0;      % STA 成功接收/响应次数
    precon_failed = 0;        % 失败/超时次数
    % precon_success_rate = 0;  % 实时成功率
    %%%%%%%%%DRL环境配置%%%%%%%%%%%
    
    % 初始化环境和智能体
    env = DownlinkSPEnv(handle, sta_num);
    if strcmpi(simulation_mode, 'RL') || strcmpi(simulation_mode, 'DQN')
        env.ablationMode = ablationMode;
        fprintf('【%s 模式】ablationMode = %s\n', simulation_mode, ablationMode);
    elseif strcmpi(simulation_mode, 'Baseline')
        fprintf('【Baseline 模式】使用策略: %s\n', baseline_method);
    end
 
    % ==================== 初始化 handle.ap.stas_info ====================
    if ~isfield(handle.ap, 'stas_info') || isempty(handle.ap.stas_info) || numel(handle.ap.stas_info) < sta_num
        fprintf('【Init】强制初始化 handle.ap.stas_info (%d 个 STA)\n', sta_num);
        
        handle.ap.stas_info = struct(...
            'sta_id',                num2cell(1:sta_num), ...
            'status',                num2cell(ones(1,sta_num)), ...
            'mac_addr',              cell(1,sta_num), ...
            'tid',                   num2cell(zeros(1,sta_num)), ...
            'control_flags',         num2cell(zeros(1,sta_num)), ...
            'control_flags_Down',    num2cell(zeros(1,sta_num)), ...
            'control_flags_DownChal',num2cell(zeros(1,sta_num)), ...
            'control_flags_UpChal',  num2cell(zeros(1,sta_num)), ...
            'seq',                   repmat({zeros(1,8)}, 1, sta_num), ...
            'tx_rate',               num2cell(100*ones(1,sta_num)), ...
            'dl_tx_info',            repmat({struct('pkt_bytes',zeros(1,8), ...
                                                     'pkt_num',zeros(1,8), ...
                                                     'tot_tx_delay',zeros(1,8), ...
                                                     'tot_tx_bagnum',zeros(1,8))},1,sta_num), ...
            'prev_dl_bytes',         num2cell(zeros(1,sta_num)), ...
            'dl_byte_this_ms',       num2cell(zeros(1,sta_num)), ...
            'dl_resv_info',          repmat({struct('Slot_Num',0,'Slot_Index',0,'Interval',0,'Time_Index',0,'Cycles_Num',0)},1,sta_num), ...
            'ul_resv_info',          repmat({struct('Slot_Num',0,'Slot_Index',0,'Interval',0,'Time_Index',0,'Cycles_Num',0)},1,sta_num), ...
            'dl_buffer',             cell(1,sta_num), ...
            'dl_buffer_seq',         num2cell(zeros(1,sta_num)), ...
            'last_used_slots',       num2cell(zeros(1,sta_num)), ...
            'last_allocated_slots',  num2cell(zeros(1,sta_num)), ...
            'actual_used_slots_this_cycle', num2cell(zeros(1,sta_num)), ...
            'actual_sent_bytes_this_cycle', num2cell(zeros(1,sta_num)), ...
            'dl_send_state',         repmat({zeros(1,10)},1,sta_num), ...
            'dl_channel',            num2cell(ones(1,sta_num)), ...
            'ul_channel',            num2cell(ones(1,sta_num)), ...
            'dl_reserve_tick',       num2cell(-ones(1,sta_num)), ...
            'history_idx',           num2cell(ones(1,sta_num)), ...
            'dl_byte_history',       repmat({zeros(1,20)},1,sta_num), ...
            'recent_rate_kbps',      num2cell(zeros(1,sta_num)), ...
            'buffer_len',            repmat({zeros(1,8)},1,sta_num), ...
            'mcs_update_info',       repmat({struct('mcs_val',3,'failed_num',0,'count',0,'start_time_tick',0,'restricted_mcs',9,'time_lock',-1)},1,sta_num), ...
            'ul_mcs_info',           repmat({ones(1,8)},1,sta_num), ...
            'rx_array',              repmat({repmat(struct('frame','','time_stamp',0), 8, 2^16)},1,sta_num), ...
            'lsn',                   repmat({zeros(8,1)},1,sta_num), ...
            'fsn',                   repmat({repmat(-1,1,8)},1,sta_num), ...
            'msn',                   repmat({repmat(-1,1,8)},1,sta_num), ...
            'ack',                   repmat({{}},1,sta_num), ...
            'maxoffset',             repmat({zeros(8,1)},1,sta_num), ...
            'getcontrolnum',         num2cell(true(1,sta_num)), ...
            'ul_receive_state',      repmat({zeros(8,1)},1,sta_num), ...
            'ul_rx_delay',           repmat({zeros(8,1)},1,sta_num), ...
            'ul_rx_bagnum',          repmat({zeros(8,1)},1,sta_num));
    
        for i = 1:sta_num
            handle.ap.stas_info(i).dl_buffer = [];
            handle.ap.stas_info(i).mac_addr = '';
            
            for tid = 1:8
                handle.ap.stas_info(i).tx_queue(tid)       = myQueue();
                handle.ap.stas_info(i).retry_queue(tid)    = myQueue();
                handle.ap.stas_info(i).backup_queue(tid)   = myQueue();
                handle.ap.stas_info(i).control_queue_ell   = myQueue();
                
                handle.ap.stas_info(i).dl_tx_info(tid).pkt_bytes    = 0;
                handle.ap.stas_info(i).dl_tx_info(tid).pkt_num      = 0;
                handle.ap.stas_info(i).dl_tx_info(tid).tot_tx_delay = 0;
                handle.ap.stas_info(i).dl_tx_info(tid).tot_tx_bagnum = 0;
            end
            
            % 初始化 mcs_update_info 为 8 个 TID 的结构体
            for tid = 1:8
                handle.ap.stas_info(i).mcs_update_info(tid) = struct('mcs_val',3,'failed_num',0,'count',0,'start_time_tick',0,'restricted_mcs',9,'time_lock',-1);
            end
        end 
        fprintf('【Init】stas_info 初始化完成！\n');
    end
    % =====================================================================
    
    
    % fprintf('当前动作空间实际大小 = %d\n', length(actInfo.Elements));
    
    if strcmpi(simulation_mode, 'DQN')
        obsInfo = getObservationInfo(env);
        actInfo = getActionInfo(env);
        agent = rlDQNAgent(obsInfo, actInfo);
        agent.AgentOptions.TargetSmoothFactor = 1e-3;
        agent.AgentOptions.MiniBatchSize = 64;
        agent.AgentOptions.ExperienceBufferLength = 100000;
        experienceBuffer = [];
    else
        agent = createD3QNAgent(env);
        experienceBuffer = rlReplayMemory(getObservationInfo(env), getActionInfo(env), 100000);
    end
    % 创建经验缓冲区

    boolean buffer_seq_initialized;
    
    %%%%%%%%开始仿真%%%%%%%%
    for sidx = 1 : handle.ticks
        handle.slot_idx = sidx;
        handle.ap.slot_idx = sidx;
        for j = 1 : sta_num
            handle.stas{j}.slot_idx = sidx;
    
            %%%%%%%%%EDCA退避更新%%%%%%%%
            
            % 更新所有AC的退避计数器
            for ac_idx = 1:4
                ac_name = handle.stas{j}.get_ac_name(ac_idx);
                if handle.stas{j}.edca_backoff.(ac_name).backoff_active
                    handle.stas{j} = handle.stas{j}.update_edca_backoff(ac_name);
                end
            end 
        end
        %%%%%%%%%%%%%%%%%模拟用户在一定范围内随机移动%%%%%%%%%%%%%%
    %     if mod(sidx,200) == 0   %m每10ms移动一次，更新误码率
    %         [AZ,EL,AZ_AOA,EL_AOA] = music_times();      %获取实际波达方向及预测的AOA
    %         F = Beam_F(EL,AZ,EL_AOA,AZ_AOA,5.8e9,0.025,4,4);            %获取由估计误差导致的损失
    %         dl_snr = caculate_snr(dl_channel_width, dist, fc, dl_powerLevel, txGain,F);
    %         for mcs_idx = 1 : 8 
    %             dl_csr(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),dl_snr, dl_nbits);  
    %         end
    %         handle.dl_csr = dl_csr;
    %     end
    
        %%%%%%%%%%%%%%%%%%%%%%模拟用户随机下线%%%%%%%%%%%%%%%%%%%%%
    %     if handle.ap.sta_num == 4 && flag_offline
    %         uid_offline = handle.ap.stas_info(4).sta_id;
    %         for m = 1 : numel(handle.stas)
    %             if handle.stas{m}.uid == uid_offline
    %                handle.stas{m}.offline_req = 1;
    %                flag_offline = 0;
    %                break;
    %             end
    %         end
    %     end
        if sidx == 500 ||sidx == 1000 || sidx == 1500 || sidx == 4500 || sidx == 5500 || sidx == 6500 || sidx == 7500
            fprintf('sta num==%f\n',sta_num);
            sta_num_int = round(handle.ap.sta_num);  
            if sta_num_int >= 1
                uid_offline = handle.ap.stas_info(randi(sta_num_int)).sta_id;
            end
            % uid_offline = handle.ap.stas_info(randi([1 handle.ap.sta_num])).sta_id;
            for m = 1 : numel(handle.stas)
                if handle.stas{m}.uid == uid_offline
                   handle.stas{m}.offline_req = 1;
                   break;
                end
            end
        end
        %%%%%%%%%%%%%%%%%%%测试下行预留，将某个用户的tid设置为5%%%%%%%%%%%%%%%%%%%%%
        if flag && ~isempty(handle.ap.stas_info)
            for i = 1 : numel(handle.ap.stas_info)
                if  handle.ap.stas_info(i).sta_id ~= handle.stas{2}.uid  && handle.stas{2}.uid ~= -1 && handle.ap.stas_info(i).sta_id ~= handle.stas{1}.uid && handle.stas{1}.uid ~= -1
                    handle.ap.stas_info(i).tid = 5;
                    handle.ap.stas_info(i).control_flags_Down = 1;
                    flag = false; 
                    break;
                end
            end  
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%超时处理流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        tsize = size(handle.timeout_process, 2);
        old_idx = [];
        for tidx = 1 : tsize
            %判断是否超时
            if handle.timeout_process(tidx).end_tick < sidx
                %超时处理,根据不同的fun_coude进行不同的处理，目前的fun_code只有1，对应超时处理
                uid = handle.timeout_process(tidx).aid;
                mac_address = handle.timeout_process(tidx).mac_addr;
                if handle.timeout_process(tidx).fun_code == 1
                    %需要接口通过aid或mac_addr找到对应的设备
                    num = numel(handle.stas);
                    for dev_idx = 1 : num
                        if((handle.stas{dev_idx}.uid == uid || strcmp(handle.stas{dev_idx}.mac_address, mac_address)))
                            handle.stas{dev_idx} = access_timeout_process(handle.stas{dev_idx});
                    %重新设置超时函数
    %                         fprintf('sta : %s timeout at tick : %d loop : %d\n', string(handle.stas{dev_idx}.mac_address), sidx, handle.stas{dev_idx}.backoff_info.loop);
                    % 当退避值减少到0时，会启动超时事件，此处不需要额外加入超时事件
    %                 fprintf('timeout tsize is %d \n',size(timeout_process, 2));                        
                        end
                    end
                elseif handle.timeout_process(tidx).fun_code == 2  %add delay event
                    mac_address = handle.timeout_process(tidx).mac_addr;
                    num = numel(handle.ap.stas_info);
                    for k = 1 : num
                        if strcmp(handle.ap.stas_info(k).mac_addr, mac_address)
                            handle.ap.stas_info(k).status = 1;
                            fprintf('sta : %d connected successfully\n', handle.ap.stas_info(k).sta_id);
                        end
                    end
                elseif handle.timeout_process(tidx).fun_code == 3   %下线请求发出
                    mac_address = handle.timeout_process(tidx).mac_addr;
                    for k = 1 : sta_num
                        if handle.stas{k}.mac_address == mac_address
                            handle.stas{k}.offline_req = 1;
                        end
                    end
                end
                old_idx = [old_idx, tidx];
            end
        end
        handle.timeout_process(old_idx) = [];%删除超时的元素
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%数据生成流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        handle = data_input(handle);   
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%调度处理流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if mod(sidx, 200) == 181   %轮询调度每10毫秒一次调度
            if ~isempty(handle.ap.stas_info)
                [handle.ap.polling_result,handle.ap.polling_idx] = gen_polling_result(handle.ap);
            %%%%结果存下来，后面等到beacon时隙，根据polling_result来进行发送
            end
            %%%%%%在最后一个ms将所有下一周期有预留需求的用户的预留状态位置2%%%%%%
            for i = 1:handle.ap.sta_num
                if handle.ap.stas_info(i).ul_resv_info.Slot_Num ~= 0   % 检查是否有预留信息
                    handle.ap.stas_info(i).control_flags = 2;
                end
            end
        end
        % 下行信道发送流程
        [handle.ap, handle.dl_channel] = dl_send(handle.ap, handle.dl_channel,handle.dl_channel_ell,handle.mcs_table);
        
        % 上行信道发送流程 (已集成EDCA)
        handle = ul_send(handle);
    
        if mod(sidx, 20) == 1     %每1ms的调度生成调度结果
            %如果用户数发生变化，需要考虑两次调度结果的用户对应关系
            handle.ap.dl_result = gen_dl_schedule_result(handle.ap,handle.mcs_table,handle.dl_channel);
    %         result_num = numel(handle.ap.dl_result);
            for k = 1 : numel(handle.ap.dl_result)
                for i = 1 : numel(handle.ap.dl_result{k})
                    dowIE_config = QbandFrameConfig;
                    dowIE_config.FrameType = 'DownIE';
                    dowIE_config.Uid = handle.ap.dl_result{k}(i).uid;
                    iecfg1 = IEConfig;
                    iecfg1.idx1 = handle.ap.dl_result{k}(i).Start_slot;
                    iecfg1.dur1 = handle.ap.dl_result{k}(i).Slot_num; 
        %                 fprintf('AP will send data_frame to STA %d,slot_num = %d\n',handle.ap.dl_result{k}(i).uid,handle.ap.dl_result{k}(i).Slot_num);
                    dowIE_config.IEConfig = iecfg1;
                    down_ie_frame = QbandGenerateMPDU([], dowIE_config);
                    %%%发送IE帧%%%%%%%
                    handle.ap.control_queue(k).push(down_ie_frame);  
                    %%%%设置AP的下行时隙状态%%%%%%
                    temp_ms = mod(ceil(sidx/20), 10);
                    if iecfg1.dur1 > 0
                        start_time1 = mod((temp_ms)*20 + iecfg1.idx1, 200);
                        handle.ap.dl_slot_states{k}(start_time1:start_time1+iecfg1.dur1 - 1) = dowIE_config.Uid;  %将用户这两个时隙内的状态置为接收
                        index = handle.ap.get_index(handle.ap.dl_result{k}(i).uid);
                        if index > 0
                            handle.ap.stas_info(index).dl_send_state(temp_ms + 1) = 1;  %当前ms有下行流量
                        end
                    end                    
                end
            end
            % 在主循环中
            if mod(sidx, 20) == 1  % 每1ms开始时（20个时隙 = 1ms）
                for i = 1:length(handle.ap.stas_info)
                    if handle.ap.stas_info(i).status == 1  % 只处理已关联用户
                        handle.ap.stas_info(i).actual_used_slots_this_cycle = 0;
                        handle.ap.stas_info(i).actual_sent_bytes_this_cycle = 0;  % 清零
                    end
                end
            end
        end
        %上行调度
        if mod(sidx,20) == 7   %第七个时隙时，一定完成了所有polling
            [handle.ap.ul_c_result,handle.ap.ul_d_result] = gen_ul_schedule_result(handle.ap,handle.mcs_table,handle.ul_channel);
    %         result_num = numel(handle.ap.ul_c_result);
            for k = 1 : numel(handle.ap.ul_c_result)
                for i = 1 : numel(handle.ap.ul_c_result{k})
                    upIE_config = QbandFrameConfig;
                    upIE_config.FrameType = 'UpIE2';  %指示控制帧
                    upIE_config.Uid = handle.ap.ul_c_result{k}(i).uid;
        %             fprintf('STA : %d schedule control_slot,sidx = %d\n',handle.ap.ul_c_result(i).uid,sidx);
        %             fprintf('STA : %d will send ARQ in %d\n',handle.ap.ul_c_result(i).uid,ceil(sidx / 20)*20 + handle.ap.ul_c_result(i).start_slot);
                    iecfg1 = IEConfig;
                    iecfg1.idx1 = handle.ap.ul_c_result{k}(i).start_slot; %数据帧放在控制帧之后
                    iecfg1.dur1 = handle.ap.ul_c_result{k}(i).slot_num;
                    iecfg1.dur2 = 0;
                    upIE_config.IEConfig = iecfg1;
                    up_ie_frame = QbandGenerateMPDU([], upIE_config);
    %                 index = handle.ap.get_index(handle.ap.ul_c_result{k}(i).uid);
                    handle.ap.control_queue(k).push(up_ie_frame);  
                    %%%%%下行预留时隙请求发送%%%%%
                    for j = 1 : numel(handle.ap.stas_info)
                        %每ms检测一次dl_reserve_tick，若其超过2说明仍未收到ack，将control_flags_Down重新置1
                        if handle.ap.stas_info(j).dl_reserve_tick ~= -1
                            handle.ap.stas_info(j).dl_reserve_tick = handle.ap.stas_info(i).dl_reserve_tick + 1;
                            if handle.ap.stas_info(j).dl_reserve_tick > 2
                                handle.ap.stas_info(j).control_flags_Down = 1;
                            end
                        end
                        if handle.ap.stas_info(j).tid == 5 && handle.ap.stas_info(j).control_flags_Down == 1     %检测下行tid，若为5且标志位为1则构造下行预留请求帧
                            max_slot_num = 4;   %最大预留时隙数目
                            used_slot_num = 0;
                            Interval = 1;       %周期默认1ms
                            Time_Index = 1;     %开始默认第一个1ms
                            Slot_Index = 18;    %从最后一个时隙往前预留
                            for n = 1 : numel(handle.ap.stas_info)     %计算已被预留的时隙数目
                                used_slot_num = used_slot_num + handle.ap.stas_info(n).dl_resv_info.Slot_Num;
                            end
                            Slot_Index = Slot_Index - used_slot_num;
                            Slot_Num = 4;       %每ms时隙数目暂定为4，后续需要计算长度
                            if used_slot_num < 4 && Slot_Num <= max_slot_num-used_slot_num
                                handle.ap.stas_info(j).dl_resv_info.Slot_Num = Slot_Num;
                            else
                                fprintf('The remained slot is not enough for reservation,STA: %d\n',handle.ap.stas_info(i).sta_id);
                                break;
                            end
                            handle.ap.stas_info(j).dl_resv_info.Slot_Index = Slot_Index;
                            handle.ap.stas_info(j).dl_resv_info.Interval = Interval;
                            handle.ap.stas_info(j).dl_resv_info.Time_Index = Time_Index;
                            handle.ap.stas_info(j).dl_resv_info.Cycles_Num = Slot_Num * 10;
                            reqframecfg = QbandFrameConfig;
                            reqframecfg.Uid = handle.ap.stas_info(j).sta_id;
                            reqframecfg.FrameType = 'PreCon_DownReq';
                            reqcfg = PreConditionConfig;
                            reqcfg.Time_Index = handle.ap.stas_info(j).dl_resv_info.Time_Index;
                            reqcfg.Interval = handle.ap.stas_info(j).dl_resv_info.Interval;
                            reqcfg.Slot_Index = handle.ap.stas_info(j).dl_resv_info.Slot_Index;
                            reqcfg.Slot_Num = handle.ap.stas_info(j).dl_resv_info.Slot_Num;
                            reqcfg.Cycles_Num = handle.ap.stas_info(j).dl_resv_info.Cycles_Num;
                            reqframecfg.PreConditionConfig = reqcfg;
                            reqframe = QbandGenerateMPDU([],reqframecfg);
                            handle.ap.control_queue(handle.ap.stas_info(j).dl_channel).push(reqframe);
                            precon_sent = precon_sent + 1;
     
                            %标志位
                            handle.ap.stas_info(j).dl_reserve_tick = 0;
                            handle.ap.stas_info(j).control_flags_Down = 2;
                            
                            % 假设成功响应（实际可根据 STA ACK 进一步精确）
                            precon_received = precon_received + 1;
                            if precon_sent > 0
                                precon_success_rate = precon_received / precon_sent;
                            end
                            fprintf('AP has created PreCon_DownReq to STA %d。\n',reqframecfg.Uid);
                        end
                     end
                end
            end
    %         result_num = numel(handle.ap.ul_d_result);
            for k = 1 : numel(handle.ap.ul_d_result)
                for i = 1 : numel(handle.ap.ul_d_result{k})
                    index = handle.ap.get_index(handle.ap.ul_d_result{k}(i).uid);
                    if index > 0
                        handle.ap.stas_info(index).buffer_len = zeros(1,8);  %将被调度到的数据报文数据清0 要不要把所有数据清0？
                    end
                    upIE_config2 = QbandFrameConfig;
                    upIE_config2.FrameType = 'UpIE1';  %指示数据帧
                    upIE_config2.Uid = handle.ap.ul_d_result{k}(i).uid;
                    iecfg2 = IEConfig;
                    iecfg2.idx1 = handle.ap.ul_d_result{k}(i).start_slot; %数据帧放在控制帧之后
                    %fprintf('ul_scedule result time_slot = %d,reslt_num = %d,sidx = %d\n',handle.ap.ul_d_result(i).slot_num,i,sidx);
                    iecfg2.dur1 = handle.ap.ul_d_result{k}(i).slot_num;
                    iecfg2.dur2 = 0;
                    upIE_config2.IEConfig = iecfg2;
                    up_ie_frame2 = QbandGenerateMPDU([], upIE_config2);
                    %%%发送IE帧%%%%%%% 
                    handle.ap.control_queue(k).push(up_ie_frame2);  
                end  
            end
            %todo 两次发送，其中一次直接入队，第二次通过延迟队列机制实现
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%下行信道发送流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        [handle.ap, handle.dl_channel] = dl_send(handle.ap, handle.dl_channel,handle.dl_channel_ell,handle.mcs_table);
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%下行信道接收流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        handle = dl_receive(handle);%指的是STA接收用户发送来的信息
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%上行信道发送流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        handle = ul_send(handle);%STA向AP发送信息
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%上行信道接收流程%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        handle = ul_receive(handle);%AP接收STA发送来的信息
       
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%时延统计%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if mod(sidx, 400) == 0  % 改为每20ms统计一次，增加样本数量
            [handle, aver_dl_tx, aver_dl_rx, aver_ul_tx, aver_ul_rx, sta_ul_delay, sta_dl_delay, sta_dl_pkt_count, sta_ul_pkt_count] = improved_delay_statistics(handle, fid, aver_dl_tx, aver_dl_rx, aver_ul_tx, aver_ul_rx);
            % 只记录有有效时延数据的STA
            for k = 1 : numel(sta_ul_delay)
                if sta_ul_delay(k) > 0  % 只记录有效时延
                    time{k} = [time{k}, sidx / 20000]; 
                    stas_ul_delay{k} = [stas_ul_delay{k}, sta_ul_delay(k)];
                end
            end
            
            for j = 1 : numel(handle.ap.ul_channel)
                ulchannel_num{j} = [ulchannel_num{j}, numel(handle.ap.ul_channel_info{j})];  
            end
            
            for k = 1 : numel(sta_dl_delay)
                if sta_dl_delay(k) > 0  % 只记录有效时延
                    time_dl{k} = [time_dl{k}, sidx / 20000]; 
                    stas_dl_delay{k} = [stas_dl_delay{k}, sta_dl_delay(k)];
                end
            end
            % ==================== 精确时延 + 包数收集（用于 Jain's Fairness） ====================
            for k = 1:sta_num
                if sta_dl_delay(k) > 0
                    delay_history(end+1) = sta_dl_delay(k);           % 记录所有有效时延
                    pkt_num = sta_dl_pkt_count(k);                    % 使用函数返回的精确包数
                    if pkt_num == 0
                        pkt_num = 1;                                  % 兜底
                    end
                    sta_delay_sum(k)  = sta_delay_sum(k)  + sta_dl_delay(k) * pkt_num;
                    sta_pkt_count(k)  = sta_pkt_count(k)  + pkt_num;
                end
            end
        end
        
        % 在主循环中，每1ms执行（与 data_input 同位置）
        if mod(sidx, 20) == 1  % 每1ms开始时
            for i = 1 : numel(handle.ap.stas_info)
                s = handle.ap.stas_info(i);
                if s.status == 0
                    continue;
                end
                
                % 取出本ms新增字节（byte → bit）
                new_bits_this_ms = s.dl_byte_this_ms * 8;
                
                % 更新环形缓冲区（最近20ms）
                idx = s.history_idx;
                s.dl_byte_history(idx) = s.dl_byte_this_ms;  % 存byte或bit都行，这里存byte
                
                % 指针前进
                s.history_idx = mod(idx, 20) + 1;
                
                % 计算最近1秒（20ms窗口）平均速率
                total_bytes_20ms = sum(s.dl_byte_history);
                total_bits_20ms  = total_bytes_20ms * 8;
                s.recent_rate_kbps = total_bits_20ms / 0.02 / 1000;  % bit/s → kbps
                
                % 可选：平滑处理
                % s.recent_rate_kbps = 0.9 * s.recent_rate_kbps + 0.1 * (new_bits_this_ms / 0.001 / 1000);
                
                handle.ap.stas_info(i) = s;
            end
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%拥塞监测(每90时隙检测一次)%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if mod(sidx,90) == 0
            for i = 1 : numel(handle.ap.dl_channel)
                if numel(handle.ap.dl_channel_info{i}) > 4 %本系统上下行基本同步，故只做下行检测
                    channelindex = 0;
                    for j = 1 : numel(handle.ap.dl_channel)   %寻找非满负载信道
                        if numel(handle.ap.dl_channel_info{j}) < 4
                            channelindex = j;
                            break;
                        end
                    end
                    if channelindex ~= 0
                        ChannelReqConfig = ChannelReqConfig;
                        ChannelReqConfig.down_channel = channelindex;
                        ChannelReqConfig.up_channel = channelindex;
                        ChannelReqConfigframe = QbandFrameConfig;
                        ChannelReqConfigframe.ChannelReqConfig = ChannelReqConfig;
                        userinfo = handle.ap.dl_channel_info{i}(1);
                        handle.ap.dl_channel_info{i}(1) = [];%从原信道将某个用户删除；
                        handle.ap.ul_channel_info{i}(1) = [];
                        handle.ap.dl_channel_info{channelindex} = [handle.ap.dl_channel_info{channelindex},userinfo];
                        handle.ap.ul_channel_info{channelindex} = [handle.ap.ul_channel_info{channelindex},userinfo];
                        handle.ap.stas_info(handle.ap.get_index(userinfo)).dl_channel = channelindex;
                        handle.ap.stas_info(handle.ap.get_index(userinfo)).ul_channel = channelindex;
                        ChannelReqConfigframe.Uid = userinfo;%随机获取第i个信道中某个用户
                        ChannelReqConfigframe.FrameType = 'ChannelReq';
                        handle.ap.control_queue(i).push(QbandGenerateMPDU([],ChannelReqConfigframe)); 
                    end
                end
            end
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%吞吐率统计(每2时隙检测一次)%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
       
        if mod(sidx, 20) == 1
            current_time = sidx / 20000;
            
            for i = 1:sta_num
                dl_throughput = 0;
                
                for j = 1:8
                    dl_throughput = dl_throughput + handle.stas{i}.mcs_update_info(j).throughput * 8 / 0.001;
                    handle.stas{i}.mcs_update_info(j).throughput = 0;
                end
                
                % 无论有没有流量都记录（关键！）
                time{i} = [time{i}, current_time];
                stas_dl_throughput{i} = [stas_dl_throughput{i}, dl_throughput / 1000];  % Kbps
            end
        end
           
        % %%%%%%%%%%%%%%%%%%%%%%%%%%%EDCA性能数据采集%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % if mod(sidx, 50) == 0  % 每50个时隙采集一次数据
        %         current_time = sidx;
        %         edca_time_points(end+1) = current_time;
        % 
        %         % 初始化当前时间点的统计数据
        %         total_retry_count = struct('AC_VO', 0, 'AC_VI', 0, 'AC_BE', 0, 'AC_BK', 0);
        %         total_success_count = struct('AC_VO', 0, 'AC_VI', 0, 'AC_BE', 0, 'AC_BK', 0);
        % 
        %         % 收集每个STA的EDC
        % A重传数据
        %         for k = 1:numel(handle.stas)
        %             if handle.stas{k}.offline_req == 2
        %                 continue; % 跳过离线STA
        %             end
        % 
        %             % 收集每个AC的重传数据
        %             ac_names = {'AC_VO', 'AC_VI', 'AC_BE', 'AC_BK'};
        %             for ac_idx = 1:length(ac_names)
        %                 ac_name = ac_names{ac_idx};
        % 
        %                 % 重传次数和成功率
        %                 if isfield(handle.stas{k}.edca_state, 'retransmission_stats') && isfield(handle.stas{k}.edca_state.retransmission_stats, ac_name)
        %                     stats = handle.stas{k}.edca_state.retransmission_stats.(ac_name);
        %                     retry_count = stats.retry_count;
        %                     success_count = stats.success_count;
        % 
        %                     total_retry_count.(ac_name) = total_retry_count.(ac_name) + retry_count;
        %                     total_success_count.(ac_name) = total_success_count.(ac_name) + success_count;
        %                 end
        %             end
        %         end
        % 
        %         % 计算整体统计数据
        %         overall_stats.time_points(end+1) = current_time;
        % 
        %         for ac_idx = 1:length(ac_names)
        %             ac_name = ac_names{ac_idx};
        % 
        %             % 平均碰撞率
        %             total_attempts = total_retry_count.(ac_name) + total_success_count.(ac_name);
        %             if total_attempts > 0
        %                 overall_stats.avg_retry_rates.(ac_name)(end+1) = total_retry_count.(ac_name) / total_attempts;
        %             else
        %                 overall_stats.avg_retry_rates.(ac_name)(end+1) = 0;
        %             end
        %         end
        % end
    
        % ====================== 多智能体 RL 决策（每10ms一次） ======================
        if mod(sidx, 200) == 0
            % ========== 步骤1：保存上一周期的使用量和分配量，并清零 ==========
            for i = 1:numel(handle.ap.stas_info)
                s = handle.ap.stas_info(i);
                if s.status == 1
                    s.last_used_slots = s.actual_used_slots_this_cycle;
                    s.last_allocated_slots = s.dl_resv_info.Slot_Num;
                    s.actual_used_slots_this_cycle = 0;
                    s.actual_sent_bytes_this_cycle = 0;
                    handle.ap.stas_info(i) = s;
                end
            end
        
            % ========== 步骤2：RL 或 Baseline 决策 ==========
            total_reward_this_step = 0;
            decision_count = 0;
            actInfo = getActionInfo(env);
            numActions = length(actInfo.Elements);
        
            if strcmpi(simulation_mode, 'RL')
                for sta_idx = 1:handle.ap.sta_num
                    s = handle.ap.stas_info(sta_idx);
                    % ========== 推荐的合理条件 ==========
                    if s.status == 1 && (s.tid >= 0 || sum([s.dl_tx_info.pkt_bytes]) > 0)
                        env.CurrentSTAIdx = sta_idx;
                        obs = env.getCurrentState();
                        currentAgent = env.Agents{sta_idx};
        
                        % ε-greedy 探索
                        if rand < 0.22
                            randIdx = randi(numActions);
                            action = actInfo.Elements{randIdx};
                        else
                            actionOutput = getAction(currentAgent, {obs});
                            action = actionOutput{1};
                        end
        
                        [nextObs, reward, isDone, ~] = env.step(action);
        
                        reward_per_sta{sta_idx}(end+1) = reward;
                        total_reward_this_step = total_reward_this_step + reward;
                        decision_count = decision_count + 1;
        
                        exp.Observation = {obs};
                        exp.Action = {action};
                        exp.Reward = reward;
                        exp.NextObservation = {nextObs};
                        exp.IsDone = isDone;
                        append(env.SharedBuffer, exp);
        
                        if isDone; env.reset(); end
                    end
                end
        
                % 训练
                if decision_count > 0
                    miniBatchSize = 64;
                    if length(env.SharedBuffer) >= miniBatchSize
                        expBatch = sample(env.SharedBuffer, miniBatchSize);
                        for i = 1:length(env.Agents)
                            env.Agents{i} = learn(env.Agents{i}, expBatch);
                        end
                    end
                end
        
            else
                % Baseline 模式（已修复）
                for sta_idx = 1:handle.ap.sta_num
                    s = handle.ap.stas_info(sta_idx);
                    if s.status == 1 && (s.tid >= 0 || sum([s.dl_tx_info.pkt_bytes]) > 0)
                        env.CurrentSTAIdx = sta_idx;
                        env.applyBaselineAction(baseline_method);   % ← 已修复
                    end
                end
            end
        
            % ========== 步骤3：记录指标 ==========
            if decision_count > 0
                reward_history(end+1) = total_reward_this_step / decision_count;
            end
            precon_usage(end+1) = env.getGlobalLoad() / env.MaxPreConNum;
            current_usage = env.getGlobalLoad() / env.MaxPreConNum;
            usage_rate_history(end+1) = current_usage;
        end
    end   
   
    % % ==================== PreCon 统计总结 ====================
    % [precon_sent, precon_received, precon_failed, precon_success_rate] = ...
    %     improved_precon_statistics(handle, precon_sent, precon_received, precon_failed, fid);
    % fprintf('PreCon 发送: %d | 接收: %d | 失败: %d | 成功率: %.2f%%\n', ...
    %     precon_sent, precon_received, precon_failed, precon_success_rate*100);
    % % =====================================================================
    % 
    % fprintf('=== 绘图前检查 ===\n');
    % fprintf('reward_history 长度: %d\n', length(reward_history));
    % fprintf('action_stats 总和: %d\n', sum(action_stats));
    % fprintf('precon_usage 长度: %d\n', length(precon_usage));
    % fprintf('最大奖励: %.2f\n', max(reward_history));
    % 
    % % ====================== 图1: RL 平均奖励曲线 ======================
    % figure('Name', 'RL Average Reward', 'Position', [100 100 800 500]);
    % plot(reward_history, 'b-', 'LineWidth', 2);
    % title('RL Average Reward over Time');
    % xlabel('决策次数 (每10ms一次)');
    % ylabel('Average Reward');
    % grid on;
    % set(gca, 'FontSize', 12);
    % drawnow;
    % shg;
    % 
    % % ====================== 图3: 全局预留时隙使用率 ======================
    % figure('Name', 'Global Pre-reservation Usage', 'Position', [500 200 800 500]);
    % plot(precon_usage, 'g-', 'LineWidth', 2);
    % title('全局预留时隙使用率');
    % xlabel('决策次数 (每10ms一次)');
    % ylabel('使用率');
    % grid on;
    % set(gca, 'FontSize', 12);
    % drawnow;
    % shg;
    % 
    % % ====================== 图5: 各STA下行接收时延 ======================
    % figure('Name', 'Per-STA Downlink Delay', 'Position', [200 300 1000 600]);
    % hold on;
    % colors = lines(min(4, sta_num));   % 自动生成不同颜色
    % for k = 1:min(4, sta_num)
    %     if ~isempty(stas_dl_delay{k})
    %         plot(time_dl{k}, stas_dl_delay{k}, ...
    %              'Color', colors(k,:), 'LineWidth', 1.8, 'DisplayName', sprintf('STA%d', k));
    %     end
    % end
    % title('各 STA 下行接收时延');
    % xlabel('时间 (秒)');
    % ylabel('时延 (ms)');
    % legend('Location', 'best');
    % grid on;
    % set(gca, 'FontSize', 12);
  % generate_edca_final_report(overall_stats, handle, stas_dl_throughput, stas_ul_delay, stas_dl_delay, time, time_dl)
    % plot_all_cdf_figures(handle, stas_ul_delay, stas_dl_delay, overall_stats);
    % ==================== 返回结果结构体（供论文使用） ====================
    % ==================== 返回结果（推荐写法） ====================
    % ==================== 返回结果（扁平结构 - 推荐现在用） ====================
    results = struct();
    
    results.simulation_mode   = simulation_mode;
    results.ablationMode      = ablationMode;
    results.sta_num           = sta_num;
    results.simulation_time   = simulation_time;
    
    results.mean_reward       = mean(reward_history);
    results.mean_usage        = mean(usage_rate_history);
    results.mean_delay        = mean(delay_history);
    results.jain_fairness     = (sum(sta_delay_sum ./ max(1,sta_pkt_count))^2) / ...
                                (sta_num * sum((sta_delay_sum ./ max(1,sta_pkt_count)).^2));
    
    results.reward_history    = reward_history;
    results.usage_rate_history = usage_rate_history;
    results.delay_history     = delay_history;
    results.reward_per_sta    = reward_per_sta;
    results.precon_usage      = precon_usage;
    
    % ==================== 临时诊断代码 ====================
    fprintf('\n【诊断】reward_history 长度 = %d\n', length(reward_history));
    fprintf('【诊断】delay_history 长度 = %d\n', length(delay_history));
    fprintf('【诊断】usage_rate_history 长度 = %d\n', length(usage_rate_history));
    fprintf('【诊断】reward_per_sta 长度 = %d\n', length(reward_per_sta));
    if ~isempty(reward_history)
        fprintf('【诊断】reward_history 前5个值: %s\n', mat2str(reward_history(1:min(5,end))));
    end
    fprintf('=====================================\n');
    save('last_run_results.mat', '-struct', 'results');
    save('last_run_results.mat', '-struct', 'results');
    
end
