function handles = ul_send(handles)      %zhao 接口类型可能需要修改，这样修改结果传不出去  %wang:组帧发送可以考虑写成一个函数，可以复用
    sta = handles.stas;
    channel = handles.ul_channel;
    channel_ell = handles.ul_channel_ell;
    slot_idx = mod(handles.slot_idx - 1, 200) + 1;
    ul_csr = handles.ul_csr;
    mcs_table = handles.mcs_table;
    %%%%%%%%EDCA竞争接入处理%%%%%%%%%%%
    handles = edca_contention_access(handles);
    
    %%%%%%%%%%遍历stas，进行上行低时延信道发送%%%%%%%%%%
    for k = 1 : numel(sta)

    %%%%%%%EDCA重传超时检查%%%%%%%%%
        need_retransmission = false;
        for ac_idx = 1:4
            ac_name = sta{k}.get_ac_name(ac_idx);
            if ~sta{k}.edca_queues.(ac_name).isempty() && ...
               sta{k}.check_retransmission_timeout(ac_name, slot_idx)
                need_retransmission = true;
                break;
            end
        end
        
        if need_retransmission
            % 处理重传超时
            for ac_idx = 1:4
                ac_name = sta{k}.get_ac_name(ac_idx);
                if ~sta{k}.edca_queues.(ac_name).isempty()
                    % 获取队列头部的帧进行重传处理
                    frame_info = sta{k}.edca_queues.(ac_name).front();
                    sta{k} = sta{k}.handle_edca_retransmission(ac_name, frame_info);
                    fprintf('STA %d %s 重传超时触发重传\n', sta{k}.uid, ac_name);
                end
            end
        end
        
        if mod(slot_idx,2) == 1 && sta{k}.Reqflag_Upchannel == 2
            packet = {};
            index = 1;
            frame = [];
            temp_length = 0;
            length = 0;
            pos = 1;
            A_mpdu_list = {};
            MU_list = {};
            %汇聚控制信息
            max_length1 = mcs_table().table_elem(1).data_rate * channel_ell.bandwith / 540 * 1e6 * 1e-4 / 8;
            while (~sta{k}.control_queue.isempty()) && ((temp_length + length) < max_length1)
                frame = sta{k}.control_queue.pop();
                packet{index} = frame;
                index = index + 1;
                temp_length = temp_length + length;
                if sta{k}.control_queue.isempty() == true
                    break
                else
                    length = size(sta{k}.control_queue.front(), 1);
                end
            end
            if logical(numel(packet))
                aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                A_mpdu_list{pos} = aggregate_frame;
                MU_list{pos}(1) = 1;  %控制帧使用最低MCS等级
                MU_list{pos}(2) = sta{k}.uid;
                pos = pos + 1;
            end
            %汇聚重传信息
            spend_time = temp_length / max_length1 * 1e-4;  
            remain_time = 1e-4 - spend_time;
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
            max_length2 = remain_time * mcs_table.table_elem(1).data_rate * 1e6 * channel_ell.bandwith / 540 / 8;
            for tid = 0 : 7
                while temp_length + length < max_length2
                    %汇聚
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        pkt_info.frame = frame;
                        pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                        sta{k}.backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
                        temp_length = temp_length + length;
                    end
                    %%%%%%zhao 需要先通过UID找到下标 todo %%%%%%%%%%%%%%%%
                    if ~sta{k}.retry_queue(tid + 1).isempty()
                        length = size(sta{k}.retry_queue(tid + 1).front(), 1);
                        if temp_length + length < max_length2
                            frame = sta{k}.retry_queue(tid + 1).pop();
                        else
                            break;
                        end
                    else
                        break;
                    end
                end           
                frame = [];
                length = 0;
            end
            if logical(numel(packet))
                aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                A_mpdu_list{pos} = aggregate_frame;
                MU_list{pos}(1) = 1;  %重传帧使用最低MCS等级
                MU_list{pos}(2) = sta{k}.uid;
                pos = pos + 1;
            end 
            %汇聚新传信息
            %提取8个tid的新传信息
            spend_time = spend_time + temp_length / max_length2 * remain_time;  
            remain_time = 1e-4 - spend_time;
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
            for tid = 0 : 7
                max_length3 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel_ell.bandwith / 540 / 8;
                while temp_length + length < max_length3  %新传帧发送
                    %汇聚
                    max_length3 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel_ell.bandwith / 540 / 8;
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        pkt_info.frame = frame;
                        pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                        sta{k}.backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
                        temp_length = temp_length + length;
                    end
                    %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                    if ~sta{k}.tx_queue(tid + 1).isempty()
                        length = size(sta{k}.tx_queue(tid + 1).front().frame, 1);
                        if temp_length + length < max_length3
                            tx_info = sta{k}.tx_queue(tid + 1).pop();
                            frame = tx_info.frame;
                            time_stamp = tx_info.time_stamp;
                            sta{k}.ul_tx_delay(tid + 1) = sta{k}.ul_tx_delay(tid + 1) + (sta{k}.slot_idx - time_stamp) * 0.05 + spend_time + (temp_length + length) / max_length3 * remain_time * 1000;  %wang:此处加上传输时延，单位为ms
                            sta{k}.ul_tx_bagnum(tid + 1) = sta{k}.ul_tx_bagnum(tid + 1) + 1;
                            %队列长度维护
                            sta{k}.pkt_bytes(tid + 1) = sta{k}.pkt_bytes(tid + 1) - length;    
                        else
                            break;
                        end    
                    else
                        break;
                    end
                end
                spend_time = spend_time + temp_length / max_length3 * remain_time;
                remain_time = 1e-4 - spend_time;
                length = 0;
                temp_length = 0;
                frame = [];
                if logical(numel(packet))
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                    A_mpdu_list{pos} = aggregate_frame;
                    MU_list{pos}(1) = sta{k}.mcs_update_info(tid + 1).mcs_val;  %wang:新传帧使用MCS等级由mcs_update_info中获取
                    MU_list{pos}(2) = sta{k}.uid;
                    pos = pos + 1;
                end
                packet = {};
                index = 1;
            end
            if pos ~= 1
                [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                channel_ell.phy_queue.push(baled_frame);
                if mod(slot_idx,20) == 1
                    fprintf('STA %d has sent data/control to AP in ELLChannel,sidx = %d\n',sta{k}.uid,handles.slot_idx);
                end
            end
            break;
        end
    end
    %%%%%%%%%%%%%%%%%%普通信道发帧%%%%%%%%%%%%%%%%%%%%%%
    for k = 1 : numel(sta)
        if sta{k}.offline_req == 2  %此时sta{k}已发出下线请求
            continue;
        end
        if mod(handles.slot_idx,20) == 1   %在每个1ms的第一个时隙重置BSR_state
            sta{k}.BSR_state = 0;
        end
        if slot_idx == 1 && sta{k}.ul_resv_info.Slot_Num ~= 0   %在每个Beacon开始时，将有预留信息的用户预留信息允许控制位true
            sta{k}.ul_resv_info.control_flags = true;
        end
        %%%%%%%%%%%%%%上行时隙预留发帧%%%%%%%%%%%%%%%%%
        if sta{k}.ul_resv_info.control_flags == true && sta{k}.ul_resv_info.Slot_Num ~= 0 && mod(slot_idx-1,20) + 1 <= sta{k}.ul_resv_info.Slot_Index && mod(slot_idx-1,20) + 1 > sta{k}.ul_resv_info.Slot_Index - sta{k}.ul_resv_info.Slot_Num  %若该用户在该时隙有预留信息，则在该时隙发送数据，并继续循环
            tid = sta{k}.tid;  %在sta结构中增添tid字段
            spend_time = 0;
            length = 0;
            frame = [];
            packet = {};
            pos = 1; %pos表示A_MPDU数组的下标
            max_length1 = mcs_table().table_elem(1).data_rate * channel{sta{k}.ul_channel}.bandwith / 540 * 1e6 * 5e-5 / 8;  %wang:考虑到信道带宽，这里要×4，计算重传帧能发的最大长度
            temp_length = 0;
            index = 1; 
            A_mpdu_list = {};
            MU_list = {};
            %遍历重传队列
            for tid = 0 : 7
                while temp_length + length < max_length1
                    %汇聚
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        pkt_info.frame = frame;
                        pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                        sta{k}.backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
                        temp_length = temp_length + length;
                    end
    
                    %%%%%%zhao 需要先通过UID找到下标 todo %%%%%%%%%%%%%%%%
                    if ~sta{k}.retry_queue(tid + 1).isempty()
                        length = size(sta{k}.retry_queue(tid + 1).front(), 1);
                        if temp_length + length < max_length1
                            frame = sta{k}.retry_queue(tid + 1).pop();
                        else
                            break;
                        end
                    else
                        break;
                    end
                end
                frame = [];
                length = 0;
            end
            if logical(numel(packet))
                aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                A_mpdu_list{pos} = aggregate_frame;
                MU_list{pos}(1) = 1;  %wang:重传帧使用最低MCS等级
                MU_list{pos}(2) = sta{k}.uid;
                pos = pos + 1;
            end
            spend_time = temp_length / max_length1 * 5e-5;  
            remain_time = 5e-5 - spend_time;
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
    %         fprintf('The MCS of STA %d new data to AP is [%d, %d, %d, %d, %d, %d, %d, %d]\n',sta{k}.uid,sta{k}.mcs_update_info(1).mcs_val,sta{k}.mcs_update_info(2).mcs_val, ...
    %                 sta{k}.mcs_update_info(3).mcs_val,sta{k}.mcs_update_info(4).mcs_val,sta{k}.mcs_update_info(5).mcs_val,sta{k}.mcs_update_info(6).mcs_val, ...
    %                 sta{k}.mcs_update_info(7).mcs_val,sta{k}.mcs_update_info(8).mcs_val);
            %遍历发送队列
            [~,TID] = sort(sta{k}.pkt_bytes,'descend');   %Xu：根据新传帧的待发送数据量对tid排序，优先发送数据量大的tid
            for tid = 0 : 7
                max_length2 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(TID(tid + 1)).mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540 / 8;
                while temp_length + length < max_length2  %新传帧发送
                    %汇聚
                    max_length2 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(TID(tid + 1)).mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540 / 8;
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        pkt_info.frame = frame;
                        pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                        sta{k}.backup_queue(TID(tid + 1)).push(pkt_info);%重新放入备份队列 
                        temp_length = temp_length + length;
                    end
                    %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                    if ~sta{k}.tx_queue(TID(tid + 1)).isempty()
                        length = size(sta{k}.tx_queue(TID(tid + 1)).front().frame, 1);
                        if temp_length + length < max_length2
                            tx_info = sta{k}.tx_queue(TID(tid + 1)).pop();
                            frame = tx_info.frame;
                            time_stamp = tx_info.time_stamp;
                            sta{k}.ul_tx_delay(TID(tid + 1)) = sta{k}.ul_tx_delay(TID(tid + 1)) + (sta{k}.slot_idx - time_stamp) * 0.05 + spend_time + (temp_length + length) / max_length2 * remain_time * 1000;  %wang:此处加上传输时延，单位为ms
                            sta{k}.ul_tx_bagnum(TID(tid + 1)) = sta{k}.ul_tx_bagnum(TID(tid + 1)) + 1;
                            %队列长度维护
                            sta{k}.pkt_bytes(TID(tid + 1)) = sta{k}.pkt_bytes(TID(tid + 1)) - length;    
                            %发送缓存备份
    %                         sta{k}.backup_queue(sta{k}.tid + 1).push(frame);
                        else
                            break;
                        end    
                    else
                        break;
                    end
                end
                spend_time = spend_time + temp_length / max_length2 * remain_time;
                remain_time = 5e-5 - spend_time;
                length = 0;
                temp_length = 0;
                frame = [];
                if logical(numel(packet))
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                    A_mpdu_list{pos} = aggregate_frame;
                    MU_list{pos}(1) = sta{k}.mcs_update_info(TID(tid + 1)).mcs_val;  %wang:新传帧使用MCS等级由mcs_update_info中获取
                    MU_list{pos}(2) = sta{k}.uid;
                    pos = pos + 1;
                end
                packet = {};
                index = 1;
            end
            %打捆
            if pos ~= 1
                [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                channel{sta{k}.ul_channel}.phy_queue.push(baled_frame);
                fprintf('STA %d has sent Pre_frame_data, sidx = %d\n',sta{k}.uid,handles.slot_idx);
            end
            continue;
        end
        
        switch sta{k}.ul_slot_states(slot_idx)
             case 256  % idle/空闲状态
                if isfield(sta{k}, 'has_sent_assoc_req') && sta{k}.has_sent_assoc_req
                    if handles.slot_idx >= sta{k}.assoc_req_slot + 35 && handles.slot_idx < sta{k}.assoc_timeout_slot
                        remaining = sta{k}.assoc_timeout_slot - handles.slot_idx;
                        if mod(remaining, 5) == 0  % 每5个时隙提醒一次
                            fprintf('STA %d AID不确定事件剩余 %d 时隙超时 (状态256)\n', sta{k}.uid, remaining);
                        end
                    end
                    if handles.slot_idx >= sta{k}.assoc_timeout_slot
                        fprintf('STA %d AID不确定事件已超时，需要处理 (状态256)\n', sta{k}.uid);
                        
                        % 检查是否超过最大重试次数
                        if ~isfield(sta{k}, 'assoc_retry_count')
                            sta{k}.assoc_retry_count = 0;
                        end
                        
                        if sta{k}.assoc_retry_count < 3
                            sta{k}.assoc_retry_count = sta{k}.assoc_retry_count + 1;
                            fprintf('STA %d 第 %d 次重试关联请求 (状态256)\n', sta{k}.uid, sta{k}.assoc_retry_count);
                            
                            % 重置退避计数器
                            sta{k}.backoff_info.loop = 1;
                            sta{k}.backoff_info.val = round(rand(1) * 20) + 1;
                            sta{k}.has_sent_assoc_req = false;
                            
                            % 将状态设置为随机接入，以便重新发送关联请求
                            sta{k}.ul_slot_states(slot_idx) = 263;
                        else
                            fprintf('STA %d 关联请求重试次数已达上限，放弃关联 (状态256)\n', sta{k}.uid);
                            sta{k}.has_sent_assoc_req = false;
                        end
                    end
                end
             case 257  % 查找AID不确定状态
                uncertain_event_count = 0;
                if isfield(handles.event_manager, 'events') && ~isempty(handles.event_manager.events)
                    for event_idx = 1:length(handles.event_manager.events)
                        event = handles.event_manager.events{event_idx};
                        if isfield(event, 'aid') && event.aid == 256
                            uncertain_event_count = uncertain_event_count + 1;
                            
                            % 检查事件是否与该STA相关
                            if isfield(event, 'mac_address') && strcmp(event.mac_address, sta{k}.mac_address)                                
                                if isfield(event, 'timeout_slot') && handles.slot_idx >= event.timeout_slot
                                    if event.event_type == 1  % 关联请求超时
                                        % 可以在这里触发重试或其他处理
                                        if ~isfield(sta{k}, 'assoc_retry_count')
                                            sta{k}.assoc_retry_count = 0;
                                        end
                                        if sta{k}.assoc_retry_count < 3
                                            % 重新尝试关联
                                            sta{k}.assoc_retry_count = sta{k}.assoc_retry_count + 1;
                                            fprintf('  STA %d 第 %d 次重试关联请求 (状态257)\n', sta{k}.uid, sta{k}.assoc_retry_count);
                                            
                                            % 重置状态为随机接入
                                            sta{k}.backoff_info.loop = 1;
                                            sta{k}.backoff_info.val = round(rand(1) * 20) + 1;
                                            sta{k}.has_sent_assoc_req = false;
                                            sta{k}.ul_slot_states(slot_idx) = 263;
                                        else
                                            fprintf('  STA %d 关联请求重试次数已达上限 (状态257)\n', sta{k}.uid);
                                            sta{k}.has_sent_assoc_req = false;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if ~isfield(handles.event_manager, 'search_history')
                    handles.event_manager.search_history = {};
                end
                
                search_record = struct();
                search_record.sta_uid = sta{k}.uid;
                search_record.slot_idx = handles.slot_idx;
                search_record.result_count = uncertain_event_count;
                search_record.search_type = 'AID_UNCERTAIN';
                handles.event_manager.search_history{end+1} = search_record;
                
                % 将状态重置为256
                sta{k}.ul_slot_states(slot_idx) = 256;
            %%%%%%%%%%%%%%上行控制发帧%%%%%%%%%%%%%%%%%
            case 259  % control_tx
                tid = sta{k}.tid; 
                length = 0;
                if ~sta{k}.control_queue.isempty()
                    length = size(sta{k}.control_queue.front(), 1);   %包的每一行为一个字节
                end
                packet = {};
                index = 1;
                temp_length = 0;
                %%%%%构造上行时隙预留请求帧%%%%%
                if sta{k}.tid == 5 && sta{k}.Reqflag    % 判断业务类型、检测请求预留标志位
                    reqcfg = PreConditionConfig;
                    reqcfg.Interval = 1;    %固定1ms一周期
                    reqcfg.Slot_Num = 4;  %这里长度需要计算
                    reqframecfg = QbandFrameConfig;
                    reqframecfg.FrameType = 'PreCon_UpReq';
                    reqframecfg.Uid = sta{k}.uid;
                    reqframecfg.PreConditionConfig = reqcfg;
                    reqframe = QbandGenerateMPDU([],reqframecfg);
                    packet{1} = reqframe;
                    sta{k}.Reqflag = false;    % 请求标志位置否
                    index = 2;
                    temp_length = size(reqframe,1);
                    fprintf('STA %d has sent PreCon_UpReq to AP,sidx = %d\n',reqframecfg.Uid,sta{k}.slot_idx);
                end
                %%%构造极低时延信道预留请求帧%%%
                if sta{k}.Reqflag_Upchannel == 1 && sta{k}.Reqflag_Downchannel == 0
                    reqcfg_chal = PreChannelConfig;
                    reqcfg_chal.RequestType = 1;        % 0请求下行信道，1请求上行信道，2均请求
                    reqframecfg_channel = QbandFrameConfig;
                    reqframecfg_channel.FrameType = 'PreChal_Req';
                    reqframecfg_channel.Uid = sta{k}.uid;
                    reqframecfg_channel.PreChannelConfig = reqcfg_chal;
                    reqframe_chal = QbandGenerateMPDU([],reqframecfg_channel);
                    packet{index} = reqframe_chal;
                    sta{k}.Reqflag_Upchannel = 0;     % 请求标志位置否
                    index = 3;
                    temp_length = size(reqframe_chal,1);
                elseif sta{k}.Reqflag_Upchannel == 0 && sta{k}.Reqflag_Downchannel == 1
                    reqcfg_chal = PreChannelConfig;
                    reqcfg_chal.RequestType = 0;        % 0请求下行信道，1请求上行信道，2均请求
                    reqframecfg_channel = QbandFrameConfig;
                    reqframecfg_channel.FrameType = 'PreChal_Req';
                    reqframecfg_channel.Uid = sta{k}.uid;
                    reqframecfg_channel.PreChannelConfig = reqcfg_chal;
                    reqframe_chal = QbandGenerateMPDU([],reqframecfg_channel);
                    packet{index} = reqframe_chal;
                    sta{k}.Reqflag_Downchannel = 0;     % 请求标志位置否
                    index = 3;
                    temp_length = size(reqframe_chal,1);                
                elseif sta{k}.Reqflag_Upchannel == 1 && sta{k}.Reqflag_Downchannel == 1
                    reqcfg_chal = PreChannelConfig;
                    reqcfg_chal.RequestType = 2;        % 0请求下行信道，1请求上行信道，2均请求
                    reqframecfg_channel = QbandFrameConfig;
                    reqframecfg_channel.FrameType = 'PreChal_Req';
                    reqframecfg_channel.Uid = sta{k}.uid;
                    reqframecfg_channel.PreChannelConfig = reqcfg_chal;
                    reqframe_chal = QbandGenerateMPDU([],reqframecfg_channel);
                    packet{index} = reqframe_chal;
                    sta{k}.Reqflag_Downchannel = 0;     % 请求标志位置否
                    sta{k}.Reqflag_Upchannel = 0;     % 请求标志位置否
                    index = 3;
                    temp_length = size(reqframe_chal,1);
                end
                 max_length = mcs_table().table_elem(1).data_rate * channel{sta{k}.ul_channel}.bandwith / 540 * 1e6 * 5e-5 / 8; %这里最大长度的计算方式后续可能还需修改 ，最大发送长度与下行对称，改为5000
                 A_mpdu_list = {};
                 MU_list = {};
                 spend_time = 0;
                 pos = 1;
                %%%%%%%%%%%%%控制帧%%%%%%%%%%%%%%
                 while (~sta{k}.control_queue.isempty()) && ((temp_length + length) < max_length)
                     %汇聚
                    frame = sta{k}.control_queue.pop();
                    packet{index} = frame;
                    index = index + 1;
                    temp_length = temp_length + length;
    %                 fprintf('STA %d has sent control_frame, sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
                    if sta{k}.control_queue.isempty() == true
                        break
                    else
                        length = size(sta{k}.control_queue.front(), 1);
                    end
                 end
                 length = 0;
                 frame = [];
                 %%%%%%%%%%%%重传帧%%%%%%%%%%%%%%
                 for tid = 0 : 7
                     if ~sta{k}.retry_queue(tid + 1).isempty()
                        length = size(sta{k}.retry_queue(tid + 1).front(), 1);   %包的每一行为一个字节
                     end
                     while (~sta{k}.retry_queue(tid + 1).isempty()) && ((temp_length + length) < max_length) %wang:考虑到重传帧和控制帧都使用最低MCS等级，将它们放在同一打捆子帧中
                         %汇聚
                        frame = sta{k}.retry_queue(tid + 1).pop();
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                        pkt_info.frame = frame;
                        pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                        sta{k}.backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
    %                     fprintf('STA %d retry_frame tid % d has been sent,sidx = %d\n',sta{k}.uid,tid,sta{k}.slot_idx);
                        if sta{k}.retry_queue(tid + 1).isempty() == true
                            break
                        else
                            length = size(sta{k}.retry_queue(tid + 1).front(), 1);
                        end
                     end
                     frame = [];
                     length = 0;
                 end
                 if logical(numel(packet))
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                    A_mpdu_list{pos} = aggregate_frame;
                    MU_list{pos}(1) = 1;  %wang:控制帧和重传帧使用最低MCS等级
                    MU_list{pos}(2) = sta{k}.uid;
                    pos = pos + 1;
                 end
                 %%%%%%%%%%%%新传帧%%%%%%%%%%%%%%
                 spend_time = temp_length / max_length * 5e-5;  
                 remain_time = 5e-5 - spend_time;
                 length = 0;
                 temp_length = 0;
                 frame = [];
                 packet = {};
                 index = 1;
                 frame = [];
                 [~,TID] = sort(sta{k}.pkt_bytes,'descend');   %Xu：根据新传帧的待发送数据量对tid排序，优先发送数据量大的tid
                 for tid = 0 : 7
                     max_length2 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(TID(tid + 1)).mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540 / 8;
                     while temp_length + length < max_length2  %新传帧发送
                        %汇聚
                        if isempty(frame) == 0
                            packet{index} = frame;
                            index = index + 1;
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                            sta{k}.backup_queue(TID(tid + 1)).push(pkt_info);%重新放入备份队列 
        %                     ap_mac.retry_frame(k,sta{k}.tid,pos).frame = frame;
        %                     ap_mac.retry_frame(k,sta{k}.tid,pos).time_stamp = ap_mac.slot_idx;%在备份队列中增设当前帧的时间戳
        %                     ap_mac.retry_frame(k,sta{k}.tid,pos).seq = seq;
        %                     a = isempty(sta{k}.backup_queue(sta{k}.tid + 1))
                            temp_length = temp_length + length;
                        end
                        %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                        if ~sta{k}.tx_queue(TID(tid + 1)).isempty()
                            length = size(sta{k}.tx_queue(TID(tid + 1)).front().frame, 1);
                            if temp_length + length < max_length2
                                tx_info = sta{k}.tx_queue(TID(tid + 1)).pop();
                                frame = tx_info.frame;
                                time_stamp = tx_info.time_stamp;
                                sta{k}.ul_tx_delay(TID(tid + 1)) = sta{k}.ul_tx_delay(TID(tid + 1)) + (sta{k}.slot_idx - time_stamp) * 0.05 + spend_time + (temp_length + length) / max_length2 * remain_time * 1000;  %wang:此处加上传输时延，单位为ms
                                sta{k}.ul_tx_bagnum(TID(tid + 1)) = sta{k}.ul_tx_bagnum(TID(tid + 1)) + 1;
                                fprintf('STA%d TID%d: slots=%d, queue_delay=%.3fms-----------------------------------------------------------------------', k, TID(tid+1), sta{k}.ul_tx_delay(TID(tid + 1)));
                                %队列长度维护
                                sta{k}.pkt_bytes(TID(tid + 1)) = sta{k}.pkt_bytes(TID(tid + 1)) - length; 
                                %发送缓存备份
        %                         sta{k}.backup_queue(sta{k}.tid + 1).push(frame);
                            else
                                break;
                            end    
                        else
                            break;
                        end
                     end
                     spend_time = spend_time + temp_length / max_length2 * remain_time;
                     remain_time = 5e-5 - spend_time;
                     length = 0;
                     temp_length = 0;
                     frame = [];
                     if index ~= 1
                        aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                        A_mpdu_list{pos} = aggregate_frame;
                        MU_list{pos}(1) = sta{k}.mcs_update_info(TID(tid + 1)).mcs_val;  
                        MU_list{pos}(2) = sta{k}.uid;
                        pos = pos + 1;
                     end 
                     packet = {};
                     index = 1;
                 end
                 if pos ~= 1
                    [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                    channel{sta{k}.ul_channel}.phy_queue.push(baled_frame);
                 end
                 sta{k}.ul_slot_states(slot_idx) = 256; %刷新时隙状态
    
            %%%%%%%%%%%%%%上行数据发帧%%%%%%%%%%%%%%%%%     
            case 258
                tid = sta{k}.tid;  %在sta结构中增添tid字段   
                packet = {};
                index = 1;
                frame = [];
                max_length = mcs_table().table_elem(1).data_rate * channel{sta{k}.ul_channel}.bandwith / 540 * 1e6 * 5e-5 / 8;%这里最大长度的计算方式后续可能还需修改   %%zhao 通过MCS获取速率的方式需要修改 %wang:速率暂时翻一倍
                temp_length = 0;
                length = 0;
                spend_time = 0;
                A_mpdu_list = {};
                MU_list = {};
                pos = 1;
                 %遍历重传队列
                 for tid = 0 : 7
                     while temp_length + length < max_length
                         %汇聚
                        if isempty(frame) == 0       %zhao frame可能没有定义
                            packet{index} = frame;
                            index = index + 1;
                            temp_length = temp_length + length;
                        end
                        if sta{k}.BSR_state == 0   %wang:此处待修改
                            data_len = sta{k}.pkt_bytes;
                            bsrframe = QbandFrameConfig;
                            bsrframe.FrameType = 'BSR';
                            bsrframe.Uid = sta{k}.uid;
                            bsrconfig = BSRConfig;
                            bsrconfig.bsrinfo = data_len;
                            bsrframe.BSRConfig = bsrconfig;
                            frame = QbandGenerateMPDU([],bsrframe); %调用构造BSR帧的函数,这里还需补充传入参数，即当前待发送数据量
                            length = size(frame,1);
                            if temp_length + length < max_length
                                sta{k}.BSR_state = 1;
                            else
                                break;
                            end
    %                         fprintf('STA %d has sent BSR to AP, sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
                        elseif sta{k}.retry_queue(tid + 1).isempty() ~= true
                            length = size(sta{k}.retry_queue(tid + 1).front(),1);
                            if temp_length + length < max_length
                                frame = sta{k}.retry_queue(tid + 1).pop();
                                pkt_info.frame = frame;
                                pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列      %slot_idx应该就在handle里面，全局维护
                                sta{k}.backup_queue(tid + 1).push(pkt_info); %重新放入备份队列 
    %                             fprintf('STA %d retry_frame tid % d has been sent,sidx = %d\n',sta{k}.uid,tid,sta{k}.slot_idx);
                            else
                                break;
                            end
                        else
                            break;
                        end
                     end
                     frame = [];
                     length = 0;
                 end
                 if index ~= 1
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);%调用聚合函数
                    A_mpdu_list{pos} = aggregate_frame;
                    MU_list{pos}(1) = 1;  %wang:重传帧使用最低MCS等级
                    MU_list{pos}(2) = sta{k}.uid;
                    pos = pos + 1;
                 end
                spend_time = temp_length / max_length * 5e-5;  
                remain_time = 5e-5 - spend_time;
                length = 0;
                temp_length = 0;
                frame = [];
                packet = {};
                index = 1;
    %             fprintf('The MCS of STA %d new data to AP is [%d, %d, %d, %d, %d, %d, %d, %d]\n',sta{k}.uid,sta{k}.mcs_update_info(1).mcs_val,sta{k}.mcs_update_info(2).mcs_val, ...
    %                 sta{k}.mcs_update_info(3).mcs_val,sta{k}.mcs_update_info(4).mcs_val,sta{k}.mcs_update_info(5).mcs_val,sta{k}.mcs_update_info(6).mcs_val, ...
    %                 sta{k}.mcs_update_info(7).mcs_val,sta{k}.mcs_update_info(8).mcs_val);
                %遍历发送队列
                [~,TID] = sort(sta{k}.pkt_bytes,'descend');   %Xu：根据新传帧的待发送数据量对tid排序，优先发送数据量大的tid
                for tid = 0 : 7
                    max_length2 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(TID(tid + 1)).mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540 / 8;
                    while temp_length + length < max_length2  %新传帧发送
                        %汇聚
                        if isempty(frame) == 0
                            packet{index} = frame;
                            index = index + 1;
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                            sta{k}.backup_queue(TID(tid + 1)).push(pkt_info);%重新放入备份队列 
                            temp_length = temp_length + length;
                        end
                        %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                        if ~sta{k}.tx_queue(TID(tid + 1)).isempty()
                            length = size(sta{k}.tx_queue(TID(tid + 1)).front().frame, 1);
                            if temp_length + length < max_length2
                                tx_info = sta{k}.tx_queue(TID(tid + 1)).pop();
    %                             fprintf('STA %d send data_frame , Tid : %d\n',sta{k}.uid ,tid);
                                frame = tx_info.frame;
                                time_stamp = tx_info.time_stamp;
                                sta{k}.ul_tx_delay(TID(tid + 1)) = sta{k}.ul_tx_delay(TID(tid + 1)) + (sta{k}.slot_idx - time_stamp) * 0.05 + spend_time + (temp_length + length) / max_length2 * remain_time * 1000;  %wang:此处加上传输时延，单位为ms
                                sta{k}.ul_tx_bagnum(TID(tid + 1)) = sta{k}.ul_tx_bagnum(TID(tid + 1)) + 1;
                                fprintf('STA%d TID%d: slots=%d, queue_delay=%.3fms-------------------------------------------', k, TID(tid+1), sta{k}.ul_tx_delay(TID(tid + 1)));
                                %队列长度维护
                                sta{k}.pkt_bytes(TID(tid + 1)) = sta{k}.pkt_bytes(TID(tid + 1)) - length;
                                %发送缓存备份
        %                         sta{k}.backup_queue(sta{k}.tid + 1).push(frame);
                            else
                                break;
                            end    
                        else
                            break;
                        end
                    end
                    spend_time = spend_time + temp_length / max_length2 * remain_time;
                    remain_time = 5e-5 - spend_time;
                    length = 0;
                    temp_length = 0;
                    frame = [];
                    if logical(numel(packet))
                        aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                        A_mpdu_list{pos} = aggregate_frame;
                        MU_list{pos}(1) = sta{k}.mcs_update_info(TID(tid + 1)).mcs_val;  
                        MU_list{pos}(2) = sta{k}.uid;
                        pos = pos + 1;
                     end 
                     packet = {};
                     index = 1;
                end
                %打捆
                if pos ~= 1
                    [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                    channel{sta{k}.ul_channel}.phy_queue.push(baled_frame);
    %                 fprintf('STA %d has sent data_frame, sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
                end
                 sta{k}.ul_slot_states(slot_idx) = 256;
            case 260  %polling_tx
                if sta{k}.offline_req == 1
                    offline_config = QbandFrameConfig;
                    offline_config.FrameType = 'OfflineReq';
                    offline_config.Address2 = sta{k}.mac_address;
                    [offline_frame, ~] = QbandFrame({offline_config});                   
                    channel{sta{k}.ul_channel}.phy_queue.push(offline_frame);
                    fprintf('STA %d send oflline-request frame\n',sta{k}.uid);
                    sta{k}.offline_req = 2;
                    continue;
                end
                tid  = sta{k}.tid ;
                data_len = sta{k}.pkt_bytes;
                bsrframe = QbandFrameConfig;
                bsrframe.FrameType = 'BSR';
                bsrframe.Uid = sta{k}.uid;
                bsrconfig = BSRConfig;
                bsrconfig.bsrinfo = data_len;
                bsrframe.BSRConfig = bsrconfig;
                BSR_frame = QbandGenerateMPDU([],bsrframe); %调用构造BSR帧的函数,这里还需补充传入参数，即当前待发送数据量
                packet{1} = BSR_frame;
                sta{k}.BSR_state = 1;
    %             fprintf('STA %d has sent BSR to AP, sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
                index = 2;
                frame = [];
                length = 0;
                spend_time = 0;
                A_mpdu_list = {};
                MU_list = {};
                pos = 1;
                temp_length = size(BSR_frame,1); 
                max_length1 = mcs_table().table_elem(1).data_rate * channel{sta{k}.ul_channel}.bandwith / 540 * 1e6 * 5e-5 / 8;%这里最大长度的计算方式后续可能还需修改   %zhao需要修改
                %遍历重传队列
                for tid = 0 : 7
                    while temp_length + length < max_length1
                        %汇聚
                        if isempty(frame) == 0
                            packet{index} = frame;
                            index = index + 1;
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                            sta{k}.backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
                            temp_length = temp_length + length;
                        end 
                        %%%%%%zhao 需要先通过UID找到下标 todo %%%%%%%%%%%%%%%%
                        if ~sta{k}.retry_queue(tid + 1).isempty()
                            length = size(sta{k}.retry_queue(tid + 1).front(), 1);
                            if temp_length + length < max_length1
                                frame = sta{k}.retry_queue(tid + 1).pop();
    %                             fprintf('STA %d retry_frame tid % d has been sent,sidx = %d\n',sta{k}.uid,tid,sta{k}.slot_idx);
                            else
                                break;
                            end
                        else
                            break;
                        end
                    end
                    frame = [];
                    length = 0;
                end
                if logical(numel(packet))
                    aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                    A_mpdu_list{pos} = aggregate_frame;
                    MU_list{pos}(1) = 1;  %wang:重传帧使用最低MCS等级
                    MU_list{pos}(2) = sta{k}.uid;
                    pos = pos + 1;
                end
                spend_time = temp_length / max_length1 * 5e-5;  
                remain_time = 5e-5 - spend_time;
                %fprintf('new data_frame MCS is %d\n',sta{k}.mcs_update_info(sta{k}.tid + 1).mcs_val);
                length = 0;
                temp_length = 0;
                frame = [];
                packet = {};
                index = 1;
                %遍历发送队列
                [~,TID] = sort(sta{k}.pkt_bytes,'descend');   %Xu：根据新传帧的待发送数据量对tid排序，优先发送数据量大的tid
                for tid = 0 : 7
                    max_length2 = remain_time * mcs_table.table_elem(sta{k}.mcs_update_info(TID(tid + 1)).mcs_val).data_rate * 1e6 * channel{sta{k}.ul_channel}.bandwith / 540 / 8;
                    while temp_length + length < max_length2  %新传帧发送
                        %汇聚
                        if isempty(frame) == 0
                            packet{index} = frame;
                            index = index + 1;
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = sta{k}.slot_idx; %将包连带时间戳一起放入队列
                            sta{k}.backup_queue(TID(tid + 1)).push(pkt_info);%重新放入备份队列 
                            temp_length = temp_length + length;
                        end
                        %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                        if ~sta{k}.tx_queue(TID(tid + 1)).isempty()
                            length = size(sta{k}.tx_queue(TID(tid + 1)).front().frame, 1);
                            if temp_length + length < max_length2
                                tx_info = sta{k}.tx_queue(TID(tid + 1)).pop();
                                frame = tx_info.frame;
                                time_stamp = tx_info.time_stamp;
                                sta{k}.ul_tx_delay(TID(tid + 1)) = sta{k}.ul_tx_delay(TID(tid + 1)) + (sta{k}.slot_idx - time_stamp) * 0.05 + spend_time + (temp_length + length) / max_length2 * remain_time * 1000;  %wang:此处加上传输时延，单位为ms
                                sta{k}.ul_tx_bagnum(TID(tid + 1)) = sta{k}.ul_tx_bagnum(TID(tid + 1)) + 1;
                                fprintf('STA%d TID%d: slots=%d, queue_delay=%.3fms----------------------------------------', k, TID(tid+1), sta{k}.ul_tx_delay(TID(tid + 1)));
                                %队列长度维护
                                sta{k}.pkt_bytes(TID(tid + 1)) = sta{k}.pkt_bytes(TID(tid + 1)) - length;  
                                %发送缓存备份
        %                         sta{k}.backup_queue(sta{k}.tid + 1).push(frame);
                            else
                                break;
                            end    
                        else
                            break;
                        end
                    end
                    spend_time = spend_time + temp_length / max_length2 * remain_time;
                    remain_time = 5e-5 - spend_time;
                    length = 0;
                    temp_length = 0;
                    frame = [];
                    if logical(numel(packet))
                        aggregate_frame = dec2hex(qbandGenerateAMPDU(packet), 2);
                        A_mpdu_list{pos} = aggregate_frame;
                        MU_list{pos}(1) = sta{k}.mcs_update_info(TID(tid + 1)).mcs_val;  
                        MU_list{pos}(2) = sta{k}.uid;
                        pos = pos + 1;
                     end 
                     packet = {};
                     index = 1;
                end
                 if pos ~= 1
                    [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                    channel{sta{k}.ul_channel}.phy_queue.push(baled_frame);
                end
                sta{k}.ul_slot_states(slot_idx) = 256;
            case 263  % random_access
                if sta{k}.status == 0    %0代表未连接    
                    %判断是否正在退避
                    if sta{k}.backoff_info.loop == 0 %还未开始退避
                        sta{k}.backoff_info.loop = 1;
                        sta{k}.backoff_info.val = round(rand(1) * 20) + 1;%暂时还没看见发生冲突怎么办
                    elseif (sta{k}.ul_slot_states(slot_idx) == 263)
                        sta{k}.backoff_info.val = sta{k}.backoff_info.val - 1;
                        if sta{k}.backoff_info.val == 0      %zhao 结合具体帧格式，此处后续需要修改
                            %退避成功，发送连接请求帧                     
                            assoc_config = QbandFrameConfig;
                            assoc_config.FrameType = 'AssocReq';
                            assoc_config.Address2 = sta{k}.mac_address;
                            [assoc_frame, ~] = QbandFrame({assoc_config});                   
                            channel{1}.phy_queue.push(assoc_frame); %wang:随机接入时还没有分配信道，暂时都使用信道1发送,如果信道1繁忙怎么办
                            channel{1}.usr_num = channel{1}.usr_num + 1;
                            fprintf('sta : %s send assocreq at tick: %d the usr_num : %d\n', string(sta{k}.mac_address), handles.slot_idx,channel{1}.usr_num );
                            %添加超时处理函数
                            %添加事件时aid不确定用256表示，查找时aid不确定用257表示
                            %添加事件时mac_addr不确定用258表示，查找时aid不确定用259表示
                            handles.timeout_process = add_delay_event(handles.timeout_process, 256, sta{k}.mac_address, handles.slot_idx + 40, 1);
                        end
                    end
                end             
        end
        handles.stas{k} = sta{k};
    end
    handles.stas = sta;
    handles.channel = channel;
end