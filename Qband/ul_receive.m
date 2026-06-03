function  handles = ul_receive( handles )
APmac = handles.ap;
channel = handles.ul_channel;
channel_ell = handles.ul_channel_ell;
user_count = numel(APmac.stas_info);
tot_size = 2^16;
thre_size = 2^15;
rx_array_size = 2^13;
csr_table = handles.ul_csr;
csr_table_ell = handles.ul_csr_ell;
timeout_flag = ones(user_count, 8);
%%%%%%%%%%%%%%%%初始化ARQ位图%%%%%%%%%%%%%%%%%%%%%%%%
if mod(APmac.slot_idx,20) == 1   
    for n = 1 : numel(APmac.stas_info)
        APmac.stas_info(n).fsn = repmat(-1, 1, 8);
        APmac.stas_info(n).msn = repmat(-1, 1, 8);
        APmac.stas_info(n).ack = cell(8,1);  %对每个user和tid + 1创建一个记录数组
        APmac.stas_info(n).maxoffset = zeros(8,1);
        APmac.stas_info(n).ul_receive_state = zeros(8,1);
    end
end
%%%%%%%%%%低时延上行信道接收%%%%%%%%%%
for k = 1 : numel(APmac.stas_info)
    slot_idx = mod(APmac.slot_idx - 1, 200) + 1;
    if APmac.stas_info(k).control_flags_UpChal == 1 && mod(slot_idx - 1, 20) + 1 == 1    % 收到信道预留请求后1ms将标志位置3，允许接收数据
        APmac.stas_info(k).control_flags_UpChal = 2;
    end
    if APmac.stas_info(k).control_flags_UpChal == 2
        count_err = 0;
        while channel_ell.phy_queue.isempty() ~= true
            frame_ell = channel_ell.phy_queue.pop();
            [sub_A_framelist, MU_list,~] = qbandBaledFrameDecode(frame_ell, 'DataFormat','Octets');
            Aframe_num_ell = numel(sub_A_framelist);
            if Aframe_num_ell == 0
                Aframe_num_ell = 1;
                sub_A_framelist{1}= frame_ell;
            end
            for m = 1 : Aframe_num_ell
                [mpdu_list_ell,~] = AMPDUDeaggregate(sub_A_framelist{m},'DataFormat','Octets');
                for sub_frame_num_ell = 1 : numel(mpdu_list_ell)
                    [mac_config,~, ~] = qbandMPDUDecode(mpdu_list_ell{sub_frame_num_ell}, 'DataFormat', 'Octets');
                    if strcmp(mac_config.FrameType,'Data')
                        %接受数据部分
%                         fprintf('AP has received Data from STA %d in ELLChannel,sidx = %d\n',mac_config.Uid,APmac.slot_idx);
                        tid = mac_config.Tid;
                        seq = mac_config.Seq;
                        uid = mac_config.Uid;
                        index = APmac.get_index(uid);
                        if index <= 0
                            continue;
                        end
                        if index > APmac.sta_num  %时序可能有问题
                            continue;
                        end
                        csr = csr_table_ell(MU_list{m}(1));
                        if rand(1) < 1 - csr
%                             fprintf('sz drop the ul_packet: Uid : %d, seq : %d , sidx: %d\n', mac_config.Uid, mac_config.Seq, APmac.slot_idx);
                            continue;
                        end
                        if mod(seq - APmac.stas_info(index).lsn(tid + 1) + tot_size,tot_size) >= thre_size
                            fprintf('error,UL_packet uid : %d seq : %d ,time_slot : %d is out of the receive_window\n',uid,seq,APmac.slot_idx);
                            count_err = count_err + 1;
                            if count_err > 10
                                fprintf('UL_send error_ell\n');
                            end
                            continue;
                        end
                        if mod(seq - APmac.stas_info(index).lsn(tid + 1) + tot_size,tot_size) < thre_size  %lsn表示每个tid + 1的接收下沿，此时表示在接收窗口内
                           if m <= numel(MU_list)
                               if MU_list{m}(1) > APmac.stas_info(index).ul_mcs_info(tid + 1) %考虑到有些帧可能是重传帧，无法代表该tid发送MCS等级，故采取此判断
                                APmac.stas_info(index).ul_mcs_info(tid + 1) = MU_list{m}(1);  %存储当前各tid上行数据的MCS等级
                               end
                           end
                           rx_info.frame = mpdu_list_ell{sub_frame_num_ell};
                           rx_info.time_stamp = APmac.slot_idx; %如果以后要计算时延，这里存储的内容要修改为时隙号 wang:改为存时隙号
                           APmac.stas_info(index).rx_array(tid + 1,(mod(seq,rx_array_size) + 1)) = rx_info;  %wang:后续需要根据index得出在stas_info数组中的下标
                           if APmac.stas_info(index).fsn(tid + 1) == -1  %当前1ms周期还没收到帧
                               APmac.stas_info(index).fsn(tid + 1) = seq;
                               APmac.stas_info(index).msn(tid + 1) = seq;
                               APmac.stas_info(index).ack{tid + 1}(seq + 1) = 1;
                           else  %wang:此处maxoffset的计算可能有问题
                               if APmac.stas_info(index).fsn(tid + 1) > seq && APmac.stas_info(index).fsn(tid + 1) - seq < thre_size  
                                   APmac.stas_info(index).fsn(tid + 1) = seq;
                               end
                               if APmac.stas_info(index).fsn(tid + 1) < seq && seq - APmac.stas_info(index).fsn(tid + 1) > thre_size
                                   APmac.stas_info(index).fsn(tid + 1) = seq;
                               end
                               if APmac.stas_info(index).msn(tid + 1) < seq && seq - APmac.stas_info(index).msn(tid + 1)< thre_size 
                                   APmac.stas_info(index).msn(tid + 1) = seq;
                               end
                               if APmac.stas_info(index).msn(tid + 1) > seq && APmac.stas_info(index).msn(tid + 1) - seq > thre_size 
                                   APmac.stas_info(index).msn(tid + 1) = seq;
                               end
                               if mod(APmac.stas_info(index).msn(tid + 1) - APmac.stas_info(index).fsn(tid + 1) + tot_size,tot_size) > APmac.stas_info(index).maxoffset(tid + 1)
                                   APmac.stas_info(index).maxoffset(tid + 1) = mod(APmac.stas_info(index).msn(tid + 1) - APmac.stas_info(index).fsn(tid + 1) + tot_size,tot_size);
                               end
                               APmac.stas_info(index).ack{tid + 1}(seq + 1) = 1; %seq序号的帧收到 wang：暂时不用偏移量设置
                           end
                        end
                        while isempty(APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame) == 0  %zhao 这里这样判断是否可行，可以考虑增加标志位  
                                %fprintf('submit ul_frame seq : %d ,index : %d,time_slot : %d\n',APmac.stas_info(index).lsn(tid + 1),index,APmac.slot_idx);
                                APmac.stas_info(index).ul_rx_delay(tid + 1) = APmac.stas_info(index).ul_rx_delay(tid + 1) + APmac.slot_idx - APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).time_stamp + 10; %wang:这里以时隙为单位，加上0.5ms解码时延
                                APmac.stas_info(index).ul_rx_bagnum(tid + 1) = APmac.stas_info(index).ul_rx_bagnum(tid + 1) + 1;
                                frame = APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame;
                                APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame = '';  %清理接收缓存数组
                                APmac.stas_info(index).lsn(tid + 1) = mod(APmac.stas_info(index).lsn(tid + 1) + 1,tot_size);
                        end
                        temp_lsn = APmac.stas_info(index).lsn(tid + 1);   %更新接收窗口下沿
                        count = 0;
                        %0218 zhao 超时处理位置需要改变，每个时隙处理一次即可
                        if timeout_flag(index, tid+1)
                            timeout_flag(index, tid+1) = 0;
                        while count < rx_array_size  %超时处理
                            while isempty(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1   %zhao 遍历找到最左边的缓存帧
                                temp_lsn = mod(temp_lsn + 1,tot_size);
                                count = count + 1;   %遍历一圈之后一定会跳出循环
                                if count > rx_array_size
                                    break;
                                end
                            end
                            if isempty(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size) + 1).frame) == 1  %此时表明整个数组都空，自然不会有超时帧
                                    break;
                            end
                            time_stamp = ceil(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size) + 1).time_stamp / 20) ;
                            temp_ms = ceil(APmac.slot_idx/20);
                            if (temp_ms - time_stamp) > 10  %超时提交
%                                 APmac.stas_info(index).dl_rx_delay(tid + 1) = APmac.stas_info(index).dl_rx_delay(tid + 1) + APmac.stas_info(index).slot_idx - APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size) + 1).time_stamp;
%                                 APmac.stas_info(index).dl_rx_bagnum(tid + 1) = APmac.stas_info(index).dl_rx_bagnum(tid + 1) + 1;
                                frame = APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame;
        %                                 clear frame;
                                APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame = '';
                                temp_lsn = mod(temp_lsn + 1,tot_size);
                                count = count + 1;
        %                                 if temp_lsn > tot_size
        %                                     temp_lsn = temp_lsn - tot_size; 
        %                                 end
                                APmac.stas_info(index).lsn(tid + 1) = temp_lsn; %更新lsn
                                fprintf('UL uid %d lsn : %d has been changed in over-time submit\n',uid,APmac.stas_info(index).lsn(tid + 1));
                            else  %此时表明lsn之后的第一个帧没有超时，即此时不存在超时帧，直接跳出超时处理
                                break;
                            end
                        end
                        end
                    elseif strcmp(mac_config.FrameType,'DownARQ')
                        %接受控制信息
%                         fprintf('AP has received DownARQ from STA %d in ELLChannel,sidx = %d\n',mac_config.Uid,APmac.slot_idx);
                        fb_info = mac_config.ARQConfig.fb_info;%获取ARQ帧的反馈信息，解包函数能解到多细粒度的字段还需协商，这里假定能拿到一个fb_info数组
                        uid = mac_config.Uid;  %发送该包的用户
                        index = APmac.get_index(uid);
                        if index <= 0
                            continue;
                        end
                        for n = 1:numel(fb_info)   %ARQ帧需要增设接收窗口下沿lsn
                            fb_info{n} = reshape(de2bi(hex2dec(fb_info{n}),8)',1,[]);
                            unit_num = fb_info{n}(1:12);
                            unit_num = comm.internal.utilities.bi2deRightMSB(unit_num, 2);
                            tid = fb_info{n}(13:16);
                            tid = comm.internal.utilities.bi2deRightMSB(tid, 2);
                            fsn = fb_info{n}(17:32);
                            fsn = comm.internal.utilities.bi2deRightMSB(fsn, 2);
                            lsn = fb_info{n}(33:48);
                            lsn = comm.internal.utilities.bi2deRightMSB(lsn, 2);
                            size = fb_info{n}(49:64);
                            size = comm.internal.utilities.bi2deRightMSB(size, 2);
                            temp_ack = fsn;  %表示实际包的序号
                            ack_bitmap = zeros(1,tot_size);  %ack bitmap
                            ack_bitmap(fsn + 1) = 1;  %fsn总表示收到的帧  

                            for l = 1:unit_num
                                fb_unit = fb_info{n}(64+(l-1)*32+1:64+(l-1)*32+32);
                                unit_type = comm.internal.utilities.bi2deRightMSB(fb_unit(1:2), 2);
                                switch unit_type
                                    case 0
                                        for seq = 1:30
                                            temp_ack = mod(temp_ack + 1,tot_size);
                                            if fb_unit(seq+2) == 1  %正确接收
                                                 ack_bitmap(temp_ack + 1) = 1; %包的序号为0~tot_size-1,数组下表为1~tot_size
                                            end
                                        end
                                    case 1
                                        for off = 0:5
                                            offset = fb_unit(2+5*off:2+5*off+4);
                                            offset = num2str(offset);
                                            offset = bin2dec(offset);
                                            if offset == 0
                                                if temp_ack + 31 > tot_size
                                                    temp_ack = temp_ack + 31 - tot_size;
                                                else
                                                    temp_ack = temp_ack + 31;
                                                end
                                            else
                                                if temp_ack + offset > tot_size
                                                    temp_ack = temp_ack + offset - tot_size;
                                                else
                                                    temp_ack = temp_ack + offset;
                                                end
                                                ack_bitmap(temp_ack) = 1;%将确认收到的帧序号对应的下标置1
                                            end
                                        end
                                    case 2
                                        for off = 0:5
                                            offset = fb_unit(2+5*off:2+5*off+4);
                                            offset = num2str(offset);
                                            offset = bin2dec(offset);
                                            if offset == 0
                                                if temp_ack + 1 > tot_size
                                                    temp_ack = temp_ack + 1 - tot_size;
                                                    ack_bitmap(temp_ack:temp_ack + 30) = 1;
                                                    temp_ack = temp_ack + 30;
                                                elseif temp_ack + 31 > tot_size
                                                    ack_bitmap(temp_ack + 1:tot_size) = 1;
                                                    temp_ack = temp_ack + 31 - tot_size;
                                                    ack_bitmap(1:temp_ack) = 1;
                                                else
                                                    ack_bitmap(temp_ack+1:temp_ack+31) = 1;
                                                    temp_ack = temp_ack + 31;
                                                end           
                                            else
                                                if temp_ack + 1 > tot_size
                                                    temp_ack = temp_ack + 1 - tot_size;
                                                    ack_bitmap(temp_ack:temp_ack + offset - 1) = 1;
                                                    temp_ack = temp_ack + offset - 1;
                                                elseif temp_ack + offset > tot_size
                                                    ack_bitmap(temp_ack + 1:tot_size) = 1;
                                                    temp_ack = temp_ack + offset - tot_size;
                                                    ack_bitmap(1:temp_ack) = 1;
                                                else
                                                    ack_bitmap(temp_ack+1:temp_ack+offset) = 1;
                                                    temp_ack = temp_ack + offset;
                                                end 
                                            end      
                                        end
                                end
                            end
                            %假定一个fb_info描述完一个tid + 1队列
                            %zhao 发送数据后下一s必须收到ARQ，调度这里需要重新考虑优化
                            %zhao 需要通过index找到数组下标，此处进行简化，后续完善
                            while ~APmac.stas_info(index).backup_queue(tid + 1).isempty()
                                pkt_info = APmac.stas_info(index).backup_queue(tid + 1).front();
                                frame = pkt_info.frame;
                                %zhao 0217 后续可以实现getseq，先用解包替代
                                [mac_config,~, ~] = qbandMPDUDecode(frame, 'DataFormat', 'Octets');
                                seq = mac_config.Seq;
                                time_stamp = ceil(pkt_info.time_stamp/20);
                                temp_time = ceil(APmac.slot_idx/20);
                                if mod((temp_time - time_stamp + 10),10) > 2
                                    fprintf('(sz)error receive the arq delay\n');
                                    fprintf('error seq : %d\n',seq);
                                    break;
                                end

                                if mod((temp_time - time_stamp + 10),10) ~= 1 && mod((temp_time - time_stamp + 10),10) ~= 2    %假定在发出包后的下1ms总能收到ARQ,第一次的ARQ会在2ms后收到
                                    break;
                                end

                                if mod((seq - lsn + tot_size),tot_size) < thre_size && ack_bitmap(seq + 1) == 0    %lsn需要在ARQ帧获取
                                        pkt_info = APmac.stas_info(index).backup_queue(tid + 1).pop();
                                        frame = pkt_info.frame; 
                                        APmac.stas_info(index).retry_queue(tid + 1).push(frame);%把包放入重传队列
%                                         fprintf('(sz) rettry the DL_packet uid : %d, seq : %d,tid : %d , sidx: %d\n', uid, seq,tid,APmac.slot_idx);
                                        APmac.stas_info(index).mcs_update_info(tid + 1) = notify_tx_failed_update(APmac.stas_info(index).mcs_update_info(tid + 1));
%                                            sta(k).backup_queue(tid + 1).push(frame);  %重新放入备份队列
                                else
                                    %不在窗口内或正确接收的帧可以出队，无需继续缓存
                                    APmac.stas_info(index).backup_queue(tid + 1).pop();
                                    APmac.stas_info(index).mcs_update_info(tid + 1) = notify_tx_succ_update(APmac.stas_info(index).mcs_update_info(tid + 1));
                                end
                            end
                           APmac.stas_info(index).mcs_update_info(tid + 1) = notify_mcs_update(APmac.stas_info(index).mcs_update_info(tid + 1),APmac.slot_idx);  %每次收到ARQ，可以进行MCS的调整
                        end  %这里已经解完所有包  
                    end
                end
            end
        end
    end
end
%%%%%%%%%%%%%%%%%%%普通信道收帧%%%%%%%%%%%%%%%%%%%%%%%
if APmac.ul_slot_states(mod(APmac.slot_idx - 1, 200) + 1) == 261  
    for channel_seq = 1 : numel(channel)  
        if channel{channel_seq}.usr_num > 1
            while ~channel{channel_seq}.phy_queue.isempty()
                channel{channel_seq}.phy_queue.pop();
            end
        else
            count_err = 0;
            while channel{channel_seq}.phy_queue.isempty() ~= true
                baled_frame = channel{channel_seq}.phy_queue.pop();
                [sub_A_mpdu, MU_list, ~] = qbandBaledFrameDecode(baled_frame,'DataFormat','Octets');         
                frame_num = numel(sub_A_mpdu);
                if frame_num == 0  %此时表示接收帧未打捆
                    frame_num = 1;
                    sub_A_mpdu{1} = baled_frame;
                end
                for m = 1:frame_num
                    [mpdu_list,~, ~] = AMPDUDeaggregate(sub_A_mpdu{m}, 'DataFormat', 'Octets');
                    for sub_frame_num = 1 : numel(mpdu_list) 
                        [mac_config,~, ~] = qbandMPDUDecode(mpdu_list{sub_frame_num}, 'DataFormat', 'Octets');
                        %%%%%%%%%%%%%%%%%%%%%%%接收数据帧%%%%%%%%%%%%%%%%%%%%%%%%%
                        if strcmp(mac_config.getType,'Data')
                            tid = mac_config.Tid;
                            seq = mac_config.Seq;
                            uid = mac_config.Uid;
                            index = APmac.get_index(uid);
                            if index <= 0
                                continue;
                            end
                            APmac.stas_info(index).ul_receive_state(tid + 1) = 1;
                            if index > APmac.sta_num  %时序可能有问题
                                continue;
                            end
                            csr = csr_table(MU_list{m}(1));
                            if rand(1) < 1 - csr
    %                             fprintf('sz drop the ul_packet: Uid : %d, seq : %d , tid = %d ,sidx: %d\n', mac_config.Uid, mac_config.Seq, tid,APmac.slot_idx);
                                continue;
                            end
                            if mod(seq - APmac.stas_info(index).lsn(tid + 1) + tot_size,tot_size) >= thre_size
                                fprintf('error,UL_packet uid : %d seq : %d , tid = %d ,time_slot : %d is out of the receive_window\n',uid,seq,tid,APmac.slot_idx);
                                count_err = count_err + 1;
                                if count_err > 10
                                    fprintf('UL_send error\n');
                                end
                                continue;
                            end
                            if mod(seq - APmac.stas_info(index).lsn(tid + 1) + tot_size,tot_size) < thre_size  %lsn表示每个tid + 1的接收下沿，此时表示在接收窗口内
                                   if m <= numel(MU_list)
                                       if MU_list{m}(1) > APmac.stas_info(index).ul_mcs_info(tid + 1) %考虑到有些帧可能是重传帧，无法代表该tid发送MCS等级，故采取此判断
                                            APmac.stas_info(index).ul_mcs_info(tid + 1) = MU_list{m}(1);  %存储当前各tid上行数据的MCS等级
                                       end
                                   end
                                   rx_info.frame = mpdu_list{sub_frame_num};
                                   rx_info.time_stamp = APmac.slot_idx; %如果以后要计算时延，这里存储的内容要修改为时隙号 wang:改为存时隙号
                                   APmac.stas_info(index).rx_array(tid + 1,(mod(seq,rx_array_size) + 1)) = rx_info;  %wang:后续需要根据index得出在stas_info数组中的下标
    %                            end
                               if APmac.stas_info(index).fsn(tid + 1) == -1  %当前1ms周期还没收到帧
                                   APmac.stas_info(index).fsn(tid + 1) = seq;
                                   APmac.stas_info(index).msn(tid + 1) = seq;
                                   APmac.stas_info(index).ack{tid + 1}(seq + 1) = 1;
                               else  %wang:此处maxoffset的计算可能有问题
                                   if APmac.stas_info(index).fsn(tid + 1) > seq && APmac.stas_info(index).fsn(tid + 1) - seq < thre_size  
    %                                    if APmac.stas_info(index).fsn(tid + 1) - seq > APmac.stas_info(index).maxoffset(tid + 1)
    %                                        APmac.stas_info(index).maxoffset(tid + 1) = APmac.stas_info(index).fsn(tid + 1) - seq;
    %                                    end
                                       APmac.stas_info(index).fsn(tid + 1) = seq;
                                   end
                                   if APmac.stas_info(index).fsn(tid + 1) < seq && seq - APmac.stas_info(index).fsn(tid + 1) > thre_size
    %                                    if mod(APmac.stas_info(index).fsn(tid + 1) - seq + tot_size,tot_size) > APmac.stas_info(index).maxoffset(tid + 1)
    %                                        APmac.stas_info(index).maxoffset(tid + 1) = mod(APmac.stas_info(index).fsn(tid + 1) - seq + tot_size,tot_size);
    %                                    end
                                       APmac.stas_info(index).fsn(tid + 1) = seq;
                                   end
                                   if APmac.stas_info(index).msn(tid + 1) < seq && seq - APmac.stas_info(index).msn(tid + 1)< thre_size 
                                       APmac.stas_info(index).msn(tid + 1) = seq;
                                   end
                                   if APmac.stas_info(index).msn(tid + 1) > seq && APmac.stas_info(index).msn(tid + 1) - seq > thre_size 
                                       APmac.stas_info(index).msn(tid + 1) = seq;
                                   end
                                   if mod(APmac.stas_info(index).msn(tid + 1) - APmac.stas_info(index).fsn(tid + 1) + tot_size,tot_size) > APmac.stas_info(index).maxoffset(tid + 1)
                                       APmac.stas_info(index).maxoffset(tid + 1) = mod(APmac.stas_info(index).msn(tid + 1) - APmac.stas_info(index).fsn(tid + 1) + tot_size,tot_size);
                                   end
                                   APmac.stas_info(index).ack{tid + 1}(seq + 1) = 1; %seq序号的帧收到 wang：暂时不用偏移量设置
                               end
                            end
                            while isempty(APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame) == 0  %zhao 这里这样判断是否可行，可以考虑增加标志位  
                                %fprintf('submit ul_frame seq : %d ,index : %d,time_slot : %d\n',APmac.stas_info(index).lsn(tid + 1),index,APmac.slot_idx);
                                APmac.stas_info(index).ul_rx_delay(tid + 1) = APmac.stas_info(index).ul_rx_delay(tid + 1) + APmac.slot_idx - APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).time_stamp + 10; %wang:这里以时隙为单位，加上0.5ms解码时延
                                APmac.stas_info(index).ul_rx_bagnum(tid + 1) = APmac.stas_info(index).ul_rx_bagnum(tid + 1) + 1;
                                frame = APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame;
    %                             fprintf('(sz) submit frame index : %d seq : %d \n', mac_config.index, mac_config.Seq);
    %                             clear frame;         %zhao 似乎无效释放，这里直接清零应该就可以了，或者存进去的时候就应该clear
                                %wang:这里计算接收时延
    %                             APmac.stas_info(index).dl_rx_delay(tid + 1) = APmac.stas_info(index).dl_rx_delay(tid + 1) + APmac.stas_info(index).slot_idx - APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size) + 1).time_stamp;
    %                             APmac.stas_info(index).dl_rx_bagnum(tid + 1) = APmac.stas_info(index).dl_rx_bagnum(tid + 1) + 1;
                                APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size)+1).frame = '';  %清理接收缓存数组
                                APmac.stas_info(index).lsn(tid + 1) = mod(APmac.stas_info(index).lsn(tid + 1) + 1,tot_size);
    %                             if APmac.stas_info(index).lsn(tid + 1) > tot_size
    %                                APmac.stas_info(index).lsn(tid + 1) = APmac.stas_info(index).lsn(tid) - tot_size; 
    %                             end
                            end
                            temp_lsn = APmac.stas_info(index).lsn(tid + 1);   %更新接收窗口下沿
                            count = 0;
                            %0218 zhao 超时处理位置需要改变，每个时隙处理一次即可
                            if timeout_flag(index, tid+1) 
                                timeout_flag(index, tid+1) = 0;
                            while count < rx_array_size  %超时处理
                                while isempty(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1   %zhao 遍历找到最左边的缓存帧
                                    temp_lsn = mod(temp_lsn + 1,tot_size);
                                    count = count + 1;   %遍历一圈之后一定会跳出循环
                                    if count > rx_array_size
                                        break;
                                    end
                                end
                                if isempty(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size) + 1).frame) == 1  %此时表明整个数组都空，自然不会有超时帧
                                        break;
                                end
                                time_stamp = ceil(APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size) + 1).time_stamp / 20) ;
                                temp_ms = ceil(APmac.slot_idx/20);
                                if (temp_ms - time_stamp) > 10  %超时提交
    %                                 APmac.stas_info(index).dl_rx_delay(tid + 1) = APmac.stas_info(index).dl_rx_delay(tid + 1) + APmac.stas_info(index).slot_idx - APmac.stas_info(index).rx_array(tid + 1,mod(APmac.stas_info(index).lsn(tid + 1),rx_array_size) + 1).time_stamp;
    %                                 APmac.stas_info(index).dl_rx_bagnum(tid + 1) = APmac.stas_info(index).dl_rx_bagnum(tid + 1) + 1;
                                    frame = APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame;
            %                                 clear frame;
                                    APmac.stas_info(index).rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame = '';
                                    temp_lsn = mod(temp_lsn + 1,tot_size);
                                    count = count + 1;
            %                                 if temp_lsn > tot_size
            %                                     temp_lsn = temp_lsn - tot_size; 
            %                                 end
                                    APmac.stas_info(index).lsn(tid + 1) = temp_lsn; %更新lsn
                                    fprintf('UL uid %d lsn : %d tid : %dhas been changed in over-time submit\n',uid,APmac.stas_info(index).lsn(tid + 1),tid);
                                else  %此时表明lsn之后的第一个帧没有超时，即此时不存在超时帧，直接跳出超时处理
                                    break;
                                end
                            end
                            end
                        else
                            %%%%%%%%%%%%%%%%%%%%%%%接收上线/下线帧%%%%%%%%%%%%%%%%%%%%%%%%%
                            if strcmp(mac_config.FrameType,'AssocReq') %连接请求  
                                address = mac_config.AssocReqConfig.mac_address;
                                %构造连接响应帧进行发送
                                mac_config1 = QbandFrameConfig;
                                mac_config1.FrameType = 'AssocRsp';
                                mac_config1.Address1 = address;
                                assoc_rsp_config = AssocRspConfig;
                                assoc_rsp_config.mac_address = address;
                                %轮询分配上下行信道，暂时先用信道索引代替信道号
                                dl_index = mod(APmac.channel_dl_idx , numel(APmac.dl_channel)) + 1;
                                assoc_rsp_config.dl_channel = dl_index;
%                                 assoc_rsp_config.dl_channel = APmac.dl_channel(dl_index);
                                APmac.channel_dl_idx = dl_index;
                                ul_index = mod(APmac.channel_ul_idx , numel(APmac.ul_channel)) + 1;
                                assoc_rsp_config.ul_channel = ul_index;
%                                 assoc_rsp_config.ul_channel = APmac.dl_channel(dl_index);
                                APmac.channel_ul_idx = ul_index;
                                %延迟1ms插入STA，避免初始丢包
                                APmac.add_sta(address,assoc_rsp_config.dl_channel,assoc_rsp_config.ul_channel); 
                                uid = APmac.get_sta_id_from_mac(address);
                                assoc_rsp_config.uid = uid;
                                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                                handles.timeout_process = add_delay_event(handles.timeout_process, 256, address, handles.slot_idx + 20, 2);
                                fprintf('ap: receive assocReq from sta: %s \n', string(address));
                                mac_config1.AssocRspConfig = assoc_rsp_config;
                                assoc_rsp_frame = QbandGenerateMPDU([],mac_config1);
                                %帧放入控制队列进行发送
                                APmac.control_queue(1).push(assoc_rsp_frame);  %wang : 上下行在关联流程中都使用索引为1的信道
                            elseif strcmp(mac_config.FrameType,'OfflineReq')
                                address = mac_config.OfflineReqConfig.mac_address;
                                mac_config1 = QbandFrameConfig;
                                mac_config1.FrameType = 'OfflineRsp';
                                mac_config1.Address1 = address;
                                offline_rsp_config = OfflineRspConfig;
                                offline_rsp_config.mac_address = address;
                                uid = APmac.get_sta_id_from_mac(address);
                                %从原信道中删除该用户uid
                                index = find(APmac.dl_channel_info{channel_seq} == uid);
                                APmac.dl_channel_info{channel_seq}(index) = [];
                                APmac.ul_channel_info{channel_seq}(index) = [];
                                fprintf('AP receive STA %d AssocoffReq\n',uid);
                                offline_rsp_config.uid = uid;
                                mac_config1.OfflineRspConfig = offline_rsp_config;
                                offline_rsp_frame = QbandGenerateMPDU([],mac_config1);
                                %帧放入控制队列进行发送
                                APmac.control_queue(channel_seq).push(offline_rsp_frame);
                                %删除对应的sta_info
                                APmac.delete_sta(address);
                                
                            %%%%%%%%%%%%%%%%%%%%%%%接收DownARQ帧%%%%%%%%%%%%%%%%%%%%%%%%%
                            elseif strcmp(mac_config.FrameType,'DownARQ')    %下行ARQ信息  %wang:在收ARQ的时候进行MCS的调整
    %                             fprintf('AP has received DownARQ from STA %d,sidx = %d\n',mac_config.Uid,APmac.slot_idx);
                                fb_info = mac_config.ARQConfig.fb_info;%获取ARQ帧的反馈信息，解包函数能解到多细粒度的字段还需协商，这里假定能拿到一个fb_info数组
                                uid = mac_config.Uid;  %发送该包的用户
                                index = APmac.get_index(uid);
                                if index <= 0
                                    continue;
                                end
                                for n = 1:numel(fb_info)   %ARQ帧需要增设接收窗口下沿lsn
                                    fb_info{n} = reshape(de2bi(hex2dec(fb_info{n}),8)',1,[]);
                                    unit_num = fb_info{n}(1:12);
                                    unit_num = comm.internal.utilities.bi2deRightMSB(unit_num, 2);
                                    tid = fb_info{n}(13:16);
                                    tid = comm.internal.utilities.bi2deRightMSB(tid, 2);
                                    fsn = fb_info{n}(17:32);
                                    fsn = comm.internal.utilities.bi2deRightMSB(fsn, 2);
                                    lsn = fb_info{n}(33:48);
                                    lsn = comm.internal.utilities.bi2deRightMSB(lsn, 2);
                                    size = fb_info{n}(49:64);
                                    size = comm.internal.utilities.bi2deRightMSB(size, 2);
                                    temp_ack = fsn;  %表示实际包的序号
                                    ack_bitmap = zeros(1,tot_size);  %ack bitmap
                                    ack_bitmap(fsn + 1) = 1;  %fsn总表示收到的帧  
    
                                    for l = 1:unit_num
                                        fb_unit = fb_info{n}(64+(l-1)*32+1:64+(l-1)*32+32);
                                        unit_type = comm.internal.utilities.bi2deRightMSB(fb_unit(1:2), 2);
                                        switch unit_type
                                            case 0
                                                for seq = 1:30
    %                                                     if temp_ack + 1 > tot_size
    %                                                             temp_ack = temp_ack + 1 - tot_size;
    %                                                     else
    %                                                             temp_ack = temp_ack + 1;
    %                                                     end
                                                    temp_ack = mod(temp_ack + 1,tot_size);
                                                    if fb_unit(seq+2) == 1  %正确接收
                                                         ack_bitmap(temp_ack + 1) = 1; %包的序号为0~tot_size-1,数组下表为1~tot_size
                                                    end
                                                end
                                            case 1
                                                for off = 0:5
                                                    offset = fb_unit(2+5*off:2+5*off+4);
                                                    offset = num2str(offset);
                                                    offset = bin2dec(offset);
                                                    if offset == 0
                                                        if temp_ack + 31 > tot_size
                                                            temp_ack = temp_ack + 31 - tot_size;
                                                        else
                                                            temp_ack = temp_ack + 31;
                                                        end
                                                    else
                                                        if temp_ack + offset > tot_size
                                                            temp_ack = temp_ack + offset - tot_size;
                                                        else
                                                            temp_ack = temp_ack + offset;
                                                        end
                                                        ack_bitmap(temp_ack) = 1;%将确认收到的帧序号对应的下标置1
                                                    end
                                                end
                                            case 2
                                                for off = 0:5
                                                    offset = fb_unit(2+5*off:2+5*off+4);
                                                    offset = num2str(offset);
                                                    offset = bin2dec(offset);
                                                    if offset == 0
                                                        if temp_ack + 1 > tot_size
                                                            temp_ack = temp_ack + 1 - tot_size;
                                                            ack_bitmap(temp_ack:temp_ack + 30) = 1;
                                                            temp_ack = temp_ack + 30;
                                                        elseif temp_ack + 31 > tot_size
                                                            ack_bitmap(temp_ack + 1:tot_size) = 1;
                                                            temp_ack = temp_ack + 31 - tot_size;
                                                            ack_bitmap(1:temp_ack) = 1;
                                                        else
                                                            ack_bitmap(temp_ack+1:temp_ack+31) = 1;
                                                            temp_ack = temp_ack + 31;
                                                        end           
                                                    else
                                                        if temp_ack + 1 > tot_size
                                                            temp_ack = temp_ack + 1 - tot_size;
                                                            ack_bitmap(temp_ack:temp_ack + offset - 1) = 1;
                                                            temp_ack = temp_ack + offset - 1;
                                                        elseif temp_ack + offset > tot_size
                                                            ack_bitmap(temp_ack + 1:tot_size) = 1;
                                                            temp_ack = temp_ack + offset - tot_size;
                                                            ack_bitmap(1:temp_ack) = 1;
                                                        else
                                                            ack_bitmap(temp_ack+1:temp_ack+offset) = 1;
                                                            temp_ack = temp_ack + offset;
                                                        end 
                                                    end      
                                                end
                                        end
                                    end
                                    %假定一个fb_info描述完一个tid + 1队列
                                    %zhao 发送数据后下一s必须收到ARQ，调度这里需要重新考虑优化
                                    %zhao 需要通过index找到数组下标，此处进行简化，后续完善
                                    while ~APmac.stas_info(index).backup_queue(tid + 1).isempty()
                                        pkt_info = APmac.stas_info(index).backup_queue(tid + 1).front();
                                        frame = pkt_info.frame;
                                        %zhao 0217 后续可以实现getseq，先用解包替代
                                        [mac_config,~, ~] = qbandMPDUDecode(frame, 'DataFormat', 'Octets');
                                        seq = mac_config.Seq;
                                        time_stamp = ceil(pkt_info.time_stamp/20);
                                        temp_time = ceil(APmac.slot_idx/20);
                                        %test 0217 zhao 
    %                                         fprintf('(sz) the time_stamp : %d, the temp_time : %d \n', time_stamp, temp_time);
                                        if mod((temp_time - time_stamp + 10),10) > 2
                                            fprintf('(sz)error receive the arq delay\n');
                                            fprintf('error seq : %d\n',seq);
                                            break;
                                        end
    
                                        if mod((temp_time - time_stamp + 10),10) ~= 1 && mod((temp_time - time_stamp + 10),10) ~= 2    %假定在发出包后的下1ms总能收到ARQ,第一次的ARQ会在2ms后收到
                                            break;
                                        end
    
    %                                         if mod((seq - fsn + tot_size),tot_size) > size
    %                                             break;
    %                                         end
    
                                        if mod((seq - lsn + tot_size),tot_size) < thre_size && ack_bitmap(seq + 1) == 0    %lsn需要在ARQ帧获取
                                                pkt_info = APmac.stas_info(index).backup_queue(tid + 1).pop();
                                                frame = pkt_info.frame; 
                                                APmac.stas_info(index).retry_queue(tid + 1).push(frame);%把包放入重传队列
    %                                             fprintf('(sz) rettry the DL_packet uid : %d, seq : %d,tid : %d , sidx: %d\n', uid, seq,tid,APmac.slot_idx);
                                                APmac.stas_info(index).mcs_update_info(tid + 1) = notify_tx_failed_update(APmac.stas_info(index).mcs_update_info(tid + 1));
    %                                            sta(k).backup_queue(tid + 1).push(frame);  %重新放入备份队列
                                        else
                                            %不在窗口内或正确接收的帧可以出队，无需继续缓存
                                            APmac.stas_info(index).backup_queue(tid + 1).pop();
                                            APmac.stas_info(index).mcs_update_info(tid + 1) = notify_tx_succ_update(APmac.stas_info(index).mcs_update_info(tid + 1));
                                        end
                                    end
                                   APmac.stas_info(index).mcs_update_info(tid + 1) = notify_mcs_update(APmac.stas_info(index).mcs_update_info(tid + 1),APmac.slot_idx);  %每次收到ARQ，可以进行MCS的调整
                                end  %这里已经解完所有包  
                            %%%%%%%%%%%%%%%%%%%%%%%接收BSR帧%%%%%%%%%%%%%%%%%%%%%%%%%
                            elseif strcmp(mac_config.FrameType,'BSR')  %BSR帧
%                                 fprintf('AP has received BSR from STA %d,sidx = %d\n',mac_config.Uid,APmac.slot_idx);
                                bsr_info = mac_config.BSRConfig.bsrinfo;
                                uid = mac_config.Uid;
                                index = APmac.get_index(uid);
                                if index <= 0
                                    continue;
                                end
                                APmac.stas_info(index).buffer_len = reshape(bsr_info,1,[]);   %将信息存入对应结构体内
                            %%%%%%%%%%%%%%%%%%%%%%%接收ACK帧%%%%%%%%%%%%%%%%%%%%%%%%%   
                            elseif strcmp(mac_config.FrameType,'ACK') %收到ACK帧后，修改下行预留中对应标志位
                                index = APmac.get_index(mac_config.Uid);                %根据uid获取角标
                                APmac.stas_info(index).dl_reserve_tick = -1;
                                APmac.stas_info(index).control_flags_Down = 0;
                                fprintf('AP has received ACK from STA %d,sidx: %d\n',mac_config.Uid,APmac.slot_idx);
                            %%%%%%%%%%%%%%%%%%%%%%%接收PreCon_UpReq帧%%%%%%%%%%%%%%%%%%%%%%%%%
                            elseif strcmp(mac_config.FrameType,'PreCon_UpReq')   %上行预留请求帧
                                % 根据当前用户数得到可以预留的时隙数，xu目前不用根据用户数来，暂定最多留4个时隙
                                max_slot_num = 4;
                                used_slot_num = 0;
                                Interval = 1;   %周期默认1ms；
                                Time_Index = 1; %开始默认第一个1ms;
                                Slot_Index = 20;    %从最后一个时隙往前预留
                                % 得到可以预留的时隙数并和已预留的做对比，将数据存入sta_info
                                for i = user_count  %得到每ms已预留的时隙数
                                    used_slot_num = used_slot_num + APmac.stas_info(i).ul_resv_info.Slot_Num;
                                end
                                if used_slot_num < 4 && mac_config.PreConditionConfig.Slot_Num <= 4-used_slot_num
                                    Slot_Num = mac_config.PreConditionConfig.Slot_Num;
                                    Status = 0;
                                else
                                    Status = 1;
                                    Slot_Num = 4-used_slot_num;
                                end
                                % 将准备的预留信息存入数组
                                index = APmac.get_index(mac_config.Uid);
                                APmac.stas_info(index).ul_resv_info.Slot_Num = Slot_Num;
                                APmac.stas_info(index).ul_resv_info.Status = Status;
                                APmac.stas_info(index).ul_resv_info.Interval = Interval;
                                APmac.stas_info(index).ul_resv_info.Time_Index = Time_Index;
                                APmac.stas_info(index).ul_resv_info.Slot_Index = Slot_Index-used_slot_num;
                                APmac.stas_info(index).ul_resv_info.Uid = mac_config.Uid;
                                % 将标志位置1
                                APmac.stas_info(index).control_flags = 1;
                                fprintf('AP has received PreCon_UpReq from STA %d，sidx = %d\n',mac_config.Uid,APmac.slot_idx);
                            %%%%%%%%%%%%%%%%%%%%%%%接收PreChal_Req帧%%%%%%%%%%%%%%%%%%%%%%%%%    
                            elseif strcmp(mac_config.FrameType,'PreChal_Req')           %极低时延信道预留请求帧
                                UlChannel = 0;
                                DlChannel = 0;
                                Status_chal = 0;
                                if mac_config.PreChannelConfig.RequestType == 0
                                    if APmac.channel_resvnum_dl < 1
%                                         for i = 1 : 8                                   %遍历信道表
%                                             if APmac.channelmap(i) == 0
%                                                 DlChannel = i;
%                                                 APmac.channelmap(i) = 1;
%                                                 break;
%                                             end
%                                         end
                                        DlChannel = 9;
                                        UlChannel = 0;
                                        Status_chal = 1;
                                        APmac.channel_resvnum_dl = APmac.channel_resvnum_dl + 1;
                                    end
                                elseif mac_config.PreChannelConfig.RequestType == 1
                                    if APmac.channel_resvnum_ul < 1
                                        UlChannel = 10;
                                        DlChannel = 0;
                                        Status_chal = 1;
                                        APmac.channel_resvnum_ul = APmac.channel_resvnum_ul + 1;
                                        % 更换现有上行信道带宽及丢包率
                                        % wang:考虑到目前信道都是540MHz,应该不需要更新丢包率表和信道带宽信息
                                        % channel.bandwith = 540;
                                        % ul_snr = caculate_snr(540, 5, 42e9, 15, 10);
                                        % mcs_ss = handles.mcs_table.table_elem;
                                        % for mcs_idx = 1 : 8
                                        %     ul_csr(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),ul_snr, 2000);
                                        % end
                                        % handles.ul_csr = ul_csr;  %更新上行发送成功率表
                                    end
                                elseif mac_config.PreChannelConfig.RequestType == 2
                                    if APmac.channel_resvnum_ul < 1 && APmac.channel_resvnum_dl < 1
%                                         for i = 1 : 8
%                                             if APmac.channelmap(i) == 0
%                                                 DlChannel = i;
%                                                 APmac.channelmap(i) = 1;
%                                                 APmac.channel_resvnum_dl = APmac.channel_resvnum_dl + 1;
%     
%                                                 break;
%                                             end   
%                                         end
                                        DlChannel = 9;
                                        UlChannel = 10;
                                        APmac.channel_resvnum_ul = APmac.channel_resvnum_ul + 1;
                                        APmac.channel_resvnum_dl = APmac.channel_resvnum_dl + 1;
                                        % 更换现有上行信道带宽及丢包率
                                        % channel.bandwith = 540;
                                        % ul_snr = caculate_snr(540, 5, 42e9, 15, 10);
                                        % mcs_ss = handles.mcs_table.table_elem;
                                        % for mcs_idx = 1 : 8
                                        %     ul_csr(mcs_idx) = GetChunkSuccessRate (mcs_ss(mcs_idx),ul_snr, 2000);
                                        % end
                                        % handles.ul_csr = ul_csr;  %更新上行发送成功率表
                                        Status_chal = 1;
                                    end
                                end
                                rspcfg_chal = PreChannelConfig;                         %构造信道预留响应帧入队
                                rspcfg_chal.Status = Status_chal;
                                rspcfg_chal.UlChannel = UlChannel;
                                rspcfg_chal.DlChannel = DlChannel;
                                rspframecfg_chal = QbandFrameConfig;
                                rspframecfg_chal.FrameType = 'PreChal_Rsp';
                                rspframecfg_chal.Uid = mac_config.Uid;
                                rspframecfg_chal.PreChannelConfig = rspcfg_chal;
                                rspframe_chal = QbandGenerateMPDU([],rspframecfg_chal);
                                APmac.control_queue(APmac.stas_info(APmac.get_index(mac_config.Uid)).dl_channel).push(rspframe_chal);
                                if Status_chal == 1 && DlChannel ~= 0
                                    APmac.stas_info(APmac.get_index(mac_config.Uid)).control_flags_DownChal = 1;%将下行标志位置1，表示等待
                                    I = find(APmac.dl_channel_info{channel_seq} == mac_config.Uid);
                                    APmac.dl_channel_info{channel_seq}(I) = [];%从原信道将这个用户删除
                                end
                                if Status_chal == 1 && UlChannel ~= 0
                                    APmac.stas_info(APmac.get_index(mac_config.Uid)).control_flags_UpChal = 1;%将上行标志位置1，表示等待
                                    I = find(APmac.ul_channel_info{channel_seq} == mac_config.Uid);
                                    APmac.ul_channel_info{channel_seq}(I) = [];%从原信道将这个用户删除
                                end
                                fprintf('AP has created PreChal_Rsp to STA %d, sidx = %d\n',rspframecfg_chal.Uid,APmac.slot_idx);
                            end
                        end
                    end
                end
            end
        end
        channel{channel_seq}.usr_num = 0;   %接收完成，信道用户数目置零
    end
end
if APmac.sta_num ~= numel(APmac.stas_info)
    fprintf('STA ERROR !!!!!\n');
end
for k = 1 : APmac.sta_num
    if mod(APmac.slot_idx,20) == 0 && APmac.stas_info(k).status == 1
%       ac_config.transID = APmac.stas_info(k).transID;    %在sta类对象中维护transID字段表示当前控制帧的序号
%       APmac.stas_info(k).transID = mod(APmac.stas_info(k).transID + 1,2^8);
        tid_num = 0;
        fb_info = [];
        for m = 1:8  %ARQ帧的组帧函数接口需要确认
            if APmac.stas_info(k).fsn(m) ~= -1  %wang：在这里对ack做处理
                %ack{m} = 
%                 fprintf('UL_fsn = %d,tid = %d\n',APmac.stas_info(k).fsn(m),m);
                offset_bitmap = zeros(1,APmac.stas_info(k).maxoffset(m));
                for p = 1:APmac.stas_info(k).maxoffset(m)  %wang:此处有问题，原因不明
                    if mod(APmac.stas_info(k).fsn(m) + p,tot_size) + 1 <= numel(APmac.stas_info(k).ack{m}) %越界判断 wang:为什么会出现越界原因未知，这样修改测试后暂时未发现问题
                        offset_bitmap(p) = APmac.stas_info(k).ack{m}(mod(APmac.stas_info(k).fsn(m) + p,tot_size) + 1);
                    end
                end
                temp_ack = 1;
                tid_num = tid_num + 1;
                fb_info(tid_num).unit_num = ceil(APmac.stas_info(k).maxoffset(m)/30); %ack数组中对应tid的确认数组的大小就是确认的帧数量，目前暂时只构造Bitmap确认的帧
                fb_info(tid_num).tid = m - 1;
                fb_info(tid_num).fsn = APmac.stas_info(k).fsn(m);
  %              fprintf('fsn : %d,sidx : %d\n', APmac.stas_info(k).fsn(m),APmac.stas_info(k).slot_idx);
                fb_info(tid_num).size = APmac.stas_info(k).maxoffset(m);
                fb_info(tid_num).lsn = APmac.stas_info(k).lsn(m); %在ARQ帧中增加lsn字段
       %         fprintf('lsn: %d\n',APmac.stas_info(k).lsn(m));
                for n = 1:fb_info(tid_num).unit_num
                    fb_info(tid_num).fb_unit(n).unit_type = 0;
                    if temp_ack + 29 <= fb_info(tid_num).size
                        fb_info(tid_num).fb_unit(n).bitmap = offset_bitmap(temp_ack:temp_ack + 29);
                        temp_ack = temp_ack + 30;
                    else
                        fb_info(tid_num).fb_unit(n).bitmap = [offset_bitmap(temp_ack:fb_info(tid_num).size),zeros(1,temp_ack + 29 - fb_info(tid_num).size)];
                        temp_ack = temp_ack + 30;
                    end
                end
            elseif APmac.stas_info(k).fsn(m) == -1 && APmac.stas_info(k).ul_receive_state(m) == 1 %此时表示STA向AP发了包但是全部丢了或全部在接收窗口外
                tid_num = tid_num + 1;
                fb_info(tid_num).unit_num = 0;
                fb_info(tid_num).tid = m - 1;
                fb_info(tid_num).fsn = -1;
                fb_info(tid_num).size = 0;
                fb_info(tid_num).lsn = APmac.stas_info(k).lsn(m); %在ARQ帧中增加lsn字段
            end
        end
            
        %zhao 先在外面构造payload，后面考虑将payload的构造和解析移到对应的ARQ的构造和解析函数中
        if ~isempty(fb_info)
            fb_payload = cell(1,numel(fb_info));
            for m = 1 : numel(fb_info)
                fb_payload{m} = [];
                for n = 1 : fb_info(m).unit_num
                    fb_payload{m} = [fb_payload{m},comm.internal.utilities.de2biBase2RightMSB(double(fb_info(m).fb_unit(n).unit_type), 2), fb_info(m).fb_unit(n).bitmap];
                end
                unit_num = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).unit_num, 12);
                tid = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).tid, 4);
                fsn = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).fsn, 16);
                lsn = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).lsn, 16);
                tsize = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).size, 16);
                %对端不需要size,把lsn传过去即可
%                 size = comm.internal.utilities.de2biBase2RightMSB(fb_info(m).lsn, 16);
                fb_payload{m} = uint8(comm.internal.utilities.bi2deRightMSB(double(reshape([unit_num,tid,fsn,lsn,tsize,fb_payload{m}], 8, [])'), 2));
            end
            mac_config = QbandFrameConfig;
            mac_config.FrameType = 'UpARQ';
            mac_config.Uid = APmac.stas_info(k).sta_id;  %wang:暂时将index与数组下标设为一致，以后可修改
            arq_config = ARQConfig;
            arq_config.tidNum = tid_num;
            arq_config.fb_info = fb_payload;
            mac_config.ARQConfig = arq_config;
            arq_frame = QbandGenerateMPDU([], mac_config);
            
            if APmac.stas_info(k).control_flags_DownChal == 0       %将ARQ帧入队
                APmac.control_queue(APmac.stas_info(k).dl_channel).push(arq_frame);
            else
                APmac.stas_info(k).control_queue_ell.push(arq_frame);
            end
%             APmac.control_queue.push(arq_frame);%将ARQ帧入队
%             fprintf('AP has created UpARQ to STA %d ,sidx = %d\n',APmac.stas_info(k).sta_id,APmac.slot_idx);
        end
    end
end
    handles.ap = APmac;
    handles.ul_channel = channel;



