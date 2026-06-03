function  [ap_mac, channel] = dl_send(ap_mac, channel, channel_ell, mcs_table)
    tot_size = 2^16;
    thre_size = 2^15;
    rx_array_size = 2^13;
    aggregate_frame_ell = {};
    %%%%%%%%遍历stas_info，进行下行预留信道发送%%%%%%%%
    for i = 1 : numel(ap_mac.stas_info)
        slot_idx = mod(ap_mac.slot_idx - 1, 200) + 1;
        if ap_mac.stas_info(i).control_flags_DownChal == 1 && mod(slot_idx - 1, 20) + 1 == 1    % 收到信道预留请求后1ms将标志位置2，允许发送数据
            ap_mac.stas_info(i).control_flags_DownChal = 2;
        end
        if mod(slot_idx,2) == 1 && ap_mac.stas_info(i).control_flags_DownChal == 2             % 奇数时隙发送数据
            spend_time = 0;
            length = 0;
            frame = [];
            packet = {};
            max_length1 = mcs_table().table_elem(1).data_rate * channel_ell.bandwith / 540 * 1e6 * 1e-4 / 8;  %计算两个时隙重传帧能发的最大长度
            temp_length = 0;
            index = 1; 
            pos = 1;
            %提取控制信息
            while (~ap_mac.stas_info(i).control_queue_ell.isempty()) && ((temp_length + length) < max_length1)
                frame = ap_mac.stas_info(i).control_queue_ell.pop();
                packet{index} = frame;
                index = index + 1;
                temp_length = temp_length + length;
                if ap_mac.stas_info(i).control_queue_ell.isempty() == true
                    break
                else
                    length = size(ap_mac.stas_info(i).control_queue_ell.front(), 1);
                end
            end
            if logical(numel(packet))
                aggregate_frame_ell{pos} = dec2hex(qbandGenerateAMPDU(packet), 2);
                MUList{pos} = [1, ap_mac.stas_info(i).sta_id];
                pos = pos + 1;
            end 
            %提取8个tid的重传信息
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
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    if(isempty(ap_mac.stas_info))
                        break;
                    end
                    %%%%%%zhao 需要先通过UID找到下标 todo %%%%%%%%%%%%%%%%
                    if ~ap_mac.stas_info(i).retry_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(i).retry_queue(tid + 1).front(), 1);
                        if temp_length + length < max_length2
                            frame = ap_mac.stas_info(i).retry_queue(tid + 1).pop();
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(i).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
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
                aggregate_frame_ell{pos} = aggregate_frame;
                MUList{pos}(1) = 1;  %重传帧使用最低MCS等级
                MUList{pos}(2) = ap_mac.stas_info(i).sta_id; %时隙号表示uid
                pos = pos + 1;
            end
            %提取8个tid的新传信息
            spend_time = spend_time + temp_length / max_length2 * remain_time;  
            remain_time = 1e-4 - spend_time;
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
            for tid = 0 : 7
                %计算当前tid数据在剩余时间内最长发送的数量
                max_length3 = remain_time * mcs_table.table_elem(ap_mac.stas_info(i).mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel_ell.bandwith / 540 / 8;
                while temp_length + length < max_length3
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                    if ~ap_mac.stas_info(i).tx_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(i).tx_queue(tid + 1).front().frame, 1);
                        if temp_length + length < max_length3
                            tx_info = ap_mac.stas_info(i).tx_queue(tid + 1).pop();
                            frame = tx_info.frame;
                            time_stamp = tx_info.time_stamp;
                            ap_mac.stas_info(i).dl_tx_info(tid + 1).tot_tx_delay = ap_mac.stas_info(i).dl_tx_info(tid + 1).tot_tx_delay + (ap_mac.slot_idx - time_stamp) * 0.05 + (spend_time + (temp_length + length) / max_length3 * remain_time) * 1000;  %wang:此处加上传输时延，单位为ms
                            ap_mac.stas_info(i).dl_tx_info(tid + 1).tot_tx_bagnum = ap_mac.stas_info(i).dl_tx_info(tid + 1).tot_tx_bagnum + 1;
                            %队列长度维护
                            ap_mac.stas_info(i).dl_tx_info(tid + 1).pkt_bytes = ap_mac.stas_info(i).dl_tx_info(tid + 1).pkt_bytes - length;
                            ap_mac.stas_info(i).dl_tx_info(tid + 1).pkt_num = ap_mac.stas_info(i).dl_tx_info(tid + 1).pkt_num - 1;     
                            %发送缓存备份
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(i).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
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
                    aggregate_frame_ell{pos} = aggregate_frame;
                    MUList{pos}(1) = ap_mac.stas_info(i).mcs_update_info(tid + 1).mcs_val;  %wang:新传帧使用MCS等级由mcs_update_info中获取
                    MUList{pos}(2) = ap_mac.stas_info(i).sta_id;
                    pos = pos + 1;
                end
                packet = {};
                index = 1;
            end
%             fprintf('AP has sent data to STA %d in ELLChannel,sidx = %d\n',ap_mac.stas_info(i).sta_id,ap_mac.slot_idx);
        end  
    end
    if numel(aggregate_frame_ell) ~= 0
        [BaledFrame,~] = qbandGenerateBaledFrame(aggregate_frame_ell,MUList,'DataFormat','Octets');
        channel_ell.phy_queue.push(BaledFrame); 
        % ========== ELL信道统计：每个子帧算一个时隙 ==========
        used_this_send_ell = numel(aggregate_frame_ell);  % 每个聚合子帧占一个“逻辑时隙”
        
        % 由于ELL可能多个用户复用，需要遍历分配（简化：平均分配，或按MU_list长度）
        % 这里假设每个子帧对应一个用户（你的MU_list设计如此）
        for p = 1:numel(MUList)
            uid = MUList{p}(2);
            idx = ap_mac.get_index(uid);
            if idx > 0
                ap_mac.stas_info(idx).actual_used_slots_this_cycle = ap_mac.stas_info(idx).actual_used_slots_this_cycle + 1;  % 每个子帧+1
            end
        end
        % ====================================================
    end
    %%%%%%%%遍历stas_info，进行下行预留时隙发送%%%%%%%%
    for k = 1 : numel(ap_mac.stas_info)
        slot_idx = mod(ap_mac.slot_idx - 1, 200) + 1;
        if slot_idx == 1 && ap_mac.stas_info(k).dl_resv_info.Slot_Num ~= 0   % 检查是否有下行预留信息
            ap_mac.stas_info(k).control_flags_Down = 3;
        end
        if ap_mac.stas_info(k).control_flags_Down == 3 && ap_mac.stas_info(k).dl_resv_info.Slot_Num ~= 0 && mod(slot_idx-1,20) + 1 <= ap_mac.stas_info(k).dl_resv_info.Slot_Index && mod(slot_idx-1,20) + 1 > ap_mac.stas_info(k).dl_resv_info.Slot_Index - ap_mac.stas_info(k).dl_resv_info.Slot_Num
            spend_time = 0;
            length = 0;
            frame = [];
            packet = {};
            pos = 1;
            max_length1 = mcs_table().table_elem(1).data_rate * channel{ap_mac.stas_info(k).dl_channel}.bandwith / 540 * 1e6 * 5e-5 / 8;
            temp_length = 0;
            index = 1; 
            A_mpdu_list = {};
            %汇聚重传帧
            for tid = 0 : 7
                while temp_length + length < max_length1 
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    %0212test
                    if(isempty(ap_mac.stas_info))
                        break;
                    end
                    %%%%%%zhao 需要先通过UID找到下标 todo %%%%%%%%%%%%%%%%
                    if ~ap_mac.stas_info(k).retry_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(k).retry_queue(tid + 1).front(), 1);
                        if temp_length + length < max_length1
                            frame = ap_mac.stas_info(k).retry_queue(tid + 1).pop();
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(k).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列
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
                MU_list{pos}(2) = ap_mac.stas_info(k).sta_id;%UID 
                pos = pos + 1;
            end
            %汇聚新传帧
            spend_time = temp_length / max_length1 * 5e-5;  
            remain_time = 5e-5 - spend_time;
%             fprintf('new data_frame MCS is %d\n',ap_mac.stas_info(k).mcs_update_info(ap_mac.stas_info(k).tid + 1).mcs_val);
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
            for tid = 0 : 7
                %首先计算当前tid数据在剩余时间内最长发送的数量
                max_length2 = remain_time * mcs_table.table_elem(ap_mac.stas_info(k).mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel{ap_mac.stas_info(k).dl_channel}.bandwith / 540 / 8;
                while temp_length + length < max_length2  %新传帧发送
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                    if ~ap_mac.stas_info(k).tx_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(k).tx_queue(tid + 1).front().frame, 1);
                        if temp_length + length < max_length2
                            tx_info = ap_mac.stas_info(k).tx_queue(tid + 1).pop();
                            frame = tx_info.frame;
                            time_stamp = tx_info.time_stamp;
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_delay = ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_delay + (ap_mac.slot_idx - time_stamp) * 0.05 + (spend_time + (temp_length + length) / max_length2 * remain_time) * 1000;  %wang:此处加上传输时延，单位为ms
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_bagnum = ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_bagnum + 1;
                            %队列长度维护
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_bytes = ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_bytes - length;
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_num = ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_num - 1;     
                            %发送缓存备份
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(k).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
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
                    MU_list{pos}(1) = ap_mac.stas_info(k).mcs_update_info(tid + 1).mcs_val;  %wang:新传帧使用MCS等级由mcs_update_info中获取
                    MU_list{pos}(2) = ap_mac.stas_info(k).sta_id;
                    pos = pos + 1;
                end
                packet = {};
                index = 1;
            end
            if pos ~= 1
                [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                channel{ap_mac.stas_info(k).dl_channel}.phy_queue.push(baled_frame);
                used_slot_this_send = pos - 1;
                ap_mac.stas_info(k).actual_used_slots_this_cycle = ap_mac.stas_info(k).actual_used_slots_this_cycle + used_slot_this_send;
                % ========== 统计实际发送字节 ==========
                sent_bytes_this_send = 0;
                for p = 1:(pos-1)  % 每个聚合子帧
                    sent_bytes_this_send = sent_bytes_this_send + size(A_mpdu_list{p}, 1);
                end
                ap_mac.stas_info(k).actual_sent_bytes_this_cycle = ap_mac.stas_info(k).actual_sent_bytes_this_cycle + sent_bytes_this_send;
                % ======================================
                
                fprintf('AP has sent Pre_frame to STA %d, used %d slots this send, total %d this cycle\n', ap_mac.stas_info(k).sta_id, used_slot_this_send, ap_mac.stas_info(k).actual_used_slots_this_cycle);
                
                fprintf('AP has sent Pre_frame to STA %d,sidx = %d\n',ap_mac.stas_info(k).sta_id,ap_mac.slot_idx);            
            end            
        end
    end
    for channel_idx = 1 : 4
        %%%%%%%%%%%%%%%%%%%%%%%%%发送Beacon帧%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) == 257 %beacon_tx ,wang:考虑到beacon时隙所有信道都一样，这里直接取第一个信道的时隙状态做判断
            if ~isempty(ap_mac.polling_result{channel_idx}) 
                beacon = QbandFrameConfig;
                beacon.FrameType = 'Beacon';
                beacon_config = BeaconConfig;
                beacon_config.pollingBitmap = ap_mac.polling_result{channel_idx};
                beacon.BeaconConfig = beacon_config;
                beacon_frame1{1} = QbandGenerateMPDU([],beacon);
                beacon_frame1 = qbandGenerateAMPDU(beacon_frame1);
                %%beacon帧入队%%
                channel{channel_idx}.phy_queue.push(beacon_frame1);
                fprintf('AP has sent Beacon to all STAs, sidx = %d\n',ap_mac.slot_idx);
                beacon_frame1 = {[]};
            end
        %%%%%%%%%%%%%%%%%%%%%%%%%%发送数据帧%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif (ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) > 0) && (ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) < 256)
            %为了与下线模块兼容，这里需要根据uid得到用户下标
            k = ap_mac.get_index(ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1));  
            if k <= 0
                ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) = 256; %刷新发送时隙状态
                return;  %此处表示用户已下线，直接结束函数
            end 
            spend_time = 0;
            length = 0;
            frame = [];
            packet = {};
            pos = 1; 
            max_length1 = mcs_table().table_elem(1).data_rate * channel{ap_mac.stas_info(k).dl_channel}.bandwith / 540 * 1e6 * 5e-5 / 8;  %wang:考虑到信道带宽，这里要×4，计算重传帧能发的最大长度
            temp_length = 0;
            index = 1; 
            A_mpdu_list = {};
            for tid = 0 : 7  %wang:遍历各个tid的重传队列
                while temp_length + length < max_length1 
                    %汇聚
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    if(isempty(ap_mac.stas_info))
                        break;
                    end
                    if ~ap_mac.stas_info(k).retry_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(k).retry_queue(tid + 1).front(), 1);
                        if temp_length + length < max_length1
                            frame = ap_mac.stas_info(k).retry_queue(tid + 1).pop();
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(k).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
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
                MU_list{pos}(2) = ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1); %时隙号表示uid
                pos = pos + 1;
            end
            spend_time = temp_length / max_length1 * 5e-5;  
            remain_time = 5e-5 - spend_time;
%           fprintf('The MCS of new data to STA %d is [%d, %d, %d, %d, %d, %d, %d, %d] \n',ap_mac.stas_info(k).sta_id,ap_mac.stas_info(k).mcs_update_info(1).mcs_val, ...
%                    ap_mac.stas_info(k).mcs_update_info(2).mcs_val, ap_mac.stas_info(k).mcs_update_info(3).mcs_val,ap_mac.stas_info(k).mcs_update_info(4).mcs_val, ...
%                    ap_mac.stas_info(k).mcs_update_info(5).mcs_val,ap_mac.stas_info(k).mcs_update_info(6).mcs_val,ap_mac.stas_info(k).mcs_update_info(7).mcs_val, ...
%                    ap_mac.stas_info(k).mcs_update_info(8).mcs_val);
            length = 0;
            temp_length = 0;
            frame = [];
            packet = {};
            index = 1;
            for tid = 0 : 7     %遍历各个tid的发送队列
                %首先计算当前tid数据在剩余时间内最长发送的数量
                max_length2 = remain_time * mcs_table.table_elem(ap_mac.stas_info(k).mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel{ap_mac.stas_info(k).dl_channel}.bandwith / 540 / 8;
                while temp_length + length < max_length2  
                    %汇聚
                    if isempty(frame) == 0
                        packet{index} = frame;
                        index = index + 1;
                        temp_length = temp_length + length;
                    end
                    %%%%%%这里是新传帧发送%%%%%%%%%%%%%%%%%%%%
                    if ~ap_mac.stas_info(k).tx_queue(tid + 1).isempty()
                        length = size(ap_mac.stas_info(k).tx_queue(tid + 1).front().frame, 1);
                        if temp_length + length < max_length2
                            tx_info = ap_mac.stas_info(k).tx_queue(tid + 1).pop();
                            frame = tx_info.frame;
                            time_stamp = tx_info.time_stamp;
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_delay = ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_delay + (ap_mac.slot_idx - time_stamp) * 0.05 + (spend_time + (temp_length + length) / max_length2 * remain_time) * 1000;  %wang:此处加上传输时延，单位为ms
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_bagnum = ap_mac.stas_info(k).dl_tx_info(tid + 1).tot_tx_bagnum + 1;
                            %队列长度维护
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_bytes = ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_bytes - length;
                            ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_num = ap_mac.stas_info(k).dl_tx_info(tid + 1).pkt_num - 1;     
                            %发送缓存备份
                            pkt_info.frame = frame;
                            pkt_info.time_stamp = ap_mac.slot_idx; %将包连带时间戳一起放入队列
                            ap_mac.stas_info(k).backup_queue(tid + 1).push(pkt_info);%重新放入备份队列 
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
                    MU_list{pos}(1) = ap_mac.stas_info(k).mcs_update_info(tid + 1).mcs_val;  %wang:新传帧使用MCS等级由mcs_update_info中获取
                    MU_list{pos}(2) = ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1);
                    pos = pos + 1;
                end
                packet = {};
                index = 1;
            end
            %打捆
            if pos ~= 1
                [baled_frame,~] = qbandGenerateBaledFrame(A_mpdu_list,MU_list, 'DataFormat', 'Octets');
                channel{ap_mac.stas_info(k).dl_channel}.phy_queue.push(baled_frame);
                used_slot_this_send = pos - 1;
                ap_mac.stas_info(k).actual_used_slots_this_cycle = ap_mac.stas_info(k).actual_used_slots_this_cycle + used_slot_this_send;
                % ========== 统计实际发送字节 ==========
                sent_bytes_this_send = 0;
                for p = 1:(pos-1)  % 每个聚合子帧
                    sent_bytes_this_send = sent_bytes_this_send + size(A_mpdu_list{p}, 1);
                end
                ap_mac.stas_info(k).actual_sent_bytes_this_cycle = ap_mac.stas_info(k).actual_sent_bytes_this_cycle + sent_bytes_this_send;
                % ======================================
                
                fprintf('AP has sent Pre_frame to STA %d, used %d slots this send, total %d this cycle\n', ap_mac.stas_info(k).sta_id, used_slot_this_send, ap_mac.stas_info(k).actual_used_slots_this_cycle);    
                fprintf('AP has sent Pre_frame to STA %d,sidx = %d\n',ap_mac.stas_info(k).sta_id,ap_mac.slot_idx);       
    %           fprintf('AP send frame to STA %d,sidx = %d\n',ap_mac.dl_slot_states(mod(ap_mac.slot_idx - 1, 200) + 1),ap_mac.slot_idx);
            end
            ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) = 256; %刷新发送时隙状态
        %%%%%%%%%%%%%%%%%%%%%%%%%%发送控制帧%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif ap_mac.dl_slot_states{channel_idx}(mod(ap_mac.slot_idx - 1, 200) + 1) == 259
             length = 0;
             if ~ap_mac.control_queue(channel_idx).isempty()
                length = size(ap_mac.control_queue(channel_idx).front(), 1);   %包的每一行为一个字节
             end
             packet = {};
             index = 1;
             %发送上行时隙预留响应帧
             for i = 1 : numel(ap_mac.stas_info)
                if ap_mac.stas_info(i).control_flags == 1
                    rspcfg = PreConditionConfig;
                    rspcfg.Status = ap_mac.stas_info(i).ul_resv_info.Status;
                    rspcfg.Time_Index = ap_mac.stas_info(i).ul_resv_info.Time_Index;
                    rspcfg.Interval = ap_mac.stas_info(i).ul_resv_info.Interval;
                    rspcfg.Slot_Index = ap_mac.stas_info(i).ul_resv_info.Slot_Index;
                    rspcfg.Slot_Num = ap_mac.stas_info(i).ul_resv_info.Slot_Num;
                    rspcfg.Cycles_Num = ap_mac.stas_info(i).ul_resv_info.Slot_Num*10;
                    rspframecfg = QbandFrameConfig;
                    rspframecfg.Uid = ap_mac.stas_info(i).ul_resv_info.Uid;
                    rspframecfg.FrameType = 'PreCon_UpRsp';
                    rspframecfg.PreConditionConfig = rspcfg;
                    rspframe = QbandGenerateMPDU([],rspframecfg);
                    packet{index} =rspframe;
                    index = index + 1;
                    ap_mac.stas_info(i).control_flags = 0;
                    fprintf('AP has sent PreCon_UpRsp to STA %d ,sidx = %d\n',rspframecfg.Uid,ap_mac.slot_idx);
                end
             end
             max_length = mcs_table.table_elem(1).data_rate * 4 * 1e6 * 5e-5 / 8;%这里最大长度的计算方式后续可能还需修改
             temp_length = 0;
             while (~ap_mac.control_queue(channel_idx).isempty()) && ((temp_length + length) < max_length)
                 %汇聚
                frame = ap_mac.control_queue(channel_idx).pop();
                packet{index} = frame;
                index = index + 1;
                temp_length = temp_length + length;
                if ap_mac.control_queue(channel_idx).isempty() == true
                    break
                else
                    length = size(ap_mac.control_queue(channel_idx).front(), 1);
                    %fprintf('UL_control_frame len = %d\n',length);
                end
             end
             if index ~= 1
                aggregate_frame = dec2hex(qbandGenerateAMPDU(packet));              
                channel{channel_idx}.phy_queue.push(aggregate_frame);
    %             fprintf('AP has sent control_frame(including UpARQ) to all STAs,sidx = %d\n',ap_mac.slot_idx);
             end
        end
    end
end

