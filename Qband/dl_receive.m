function  handles = dl_receive(handles)   %zhao 输入输出要改，不然修改传不出来
sta = handles.stas;   %假定sta为一个sta类数组
channel = handles.dl_channel;
channel_ell = handles.dl_channel_ell;
tot_size = 2^16;
thre_size = 2^15;
rx_array_size = 2^13;
csr_table = handles.dl_csr ;  %由于包长固定，预先计算出各种MCS等级下包的发送成功率，以便提升程序运行速度
csr_table_ell = handles.dl_csr_ell;
timeout_flag = ones(numel(sta),8);
%%%%%%%%%%%%%%初始化ARQ位图%%%%%%%%%%%%%%%%%%%%%%%%
for k = 1 : numel(sta)
    if isempty(sta{k})
        continue;
    end
    if mod(sta{k}.slot_idx, 20) == 1   %在每个1ms的一开始初始化fsn，这些操作的实现位置可能要改
        sta{k}.fsn = sta{k}.fsn.^0;    
        sta{k}.fsn = sta{k}.fsn.*(-1);
        sta{k}.msn = repmat(-1, 1, 8);
        sta{k}.ack = cell(8,1);  %对每个tid创建一个记录数组
        sta{k}.maxoffset = zeros(8,1);
    end
end
%%%%%%%%%%%%%%接收极低时延信道中的包%%%%%%%%%%%%%%%%
queue_size_ell = channel_ell.phy_queue.size();
count_dl = 0;
for num_ell = 1 : queue_size_ell
    Baledframe_ell = channel_ell.phy_queue.pop();
    flag_ell = 0;  %表示当前该帧是否被sta接收的标志
    for k = 1 : numel(sta)
        [sub_A_mpdu_ell,MU_list,~] = qbandBaledFrameDecode(Baledframe_ell, 'DataFormat','Octets');
        Aframe_num_ell = numel(sub_A_mpdu_ell);
        if Aframe_num_ell == 0
            Aframe_num_ell = 1;
            sub_A_mpdu_ell{1}= Baledframe_ell;
        end
        for m = 1 : Aframe_num_ell
            [mpdu_list_ell,~,~,mpdulength] = AMPDUDeaggregate(sub_A_mpdu_ell{m},'DataFormat','Octets');
            for sub_frame_num_ell = 1 : numel(mpdu_list_ell)
                [mac_config,~, ~] = qbandMPDUDecode(mpdu_list_ell{sub_frame_num_ell}, 'DataFormat', 'Octets');
                if mac_config.Uid == sta{k}.uid   %该帧是发给当前用户的
                    flag_ell = 1;
                    if strcmp(mac_config.FrameType,'Data')
%                         fprintf('STA %d has received Data from AP in ELLChannel,sidx = %d\n',mac_config.Uid,handles.slot_idx);
                        csr = csr_table_ell(MU_list{m}(1));
                        if rand(1) < 1 - csr  
%                             fprintf('sz drop the DL_packet: uid : %d, seq : %d , tid : %d , sidx: %d\n', mac_config.Uid, mac_config.Seq,mac_config.Tid,sta{k}.slot_idx);
                            continue;
                        end
                        tid = mac_config.Tid;
                        seq = mac_config.Seq;
                        if mod(seq - sta{k}.lsn(tid + 1) + tot_size,tot_size) >= thre_size
                            fprintf('error ,uid : %d frame seq : %d is out of the receive window\n',sta{k}.uid,seq);
                            count_dl = count_dl + 1;
                            if count_dl > 10
                                fprintf('dl_send error_ell\n');
                            end
                        end
                        if mod(seq - sta{k}.lsn(tid + 1) + tot_size,tot_size) < thre_size  %lsn表示每个tid的接收下沿，此时表示在接收窗口内
                           rx_info.frame = mpdu_list_ell{sub_frame_num_ell};
                           rx_info.time_stamp = sta{k}.slot_idx;  %这里直接存储时隙号，以便计算接收时延
                           sta{k}.rx_array(tid + 1, mod(seq,rx_array_size) + 1) = rx_info;
                           if sta{k}.fsn(tid + 1) == -1  %当前1ms周期还没收到帧     %zhao 更新本周期的接收bitmap位图  %wang : 修改
                               sta{k}.fsn(tid + 1) = seq;
                               sta{k}.msn(tid + 1) = seq;
                                %fprintf('receive the packet: uid : %d, seq : %d , sidx: %d\n', mac_config.Uid, mac_config.Seq, sta{k}.slot_idx);
                               sta{k}.ack{tid + 1}(seq + 1) = 1;
                           else
                               if sta{k}.fsn(tid + 1) > seq && sta{k}.fsn(tid + 1) - seq < thre_size  
                                   sta{k}.fsn(tid + 1) = seq;
                               end
                               if sta{k}.fsn(tid + 1) < seq && seq - sta{k}.fsn(tid + 1) > thre_size
                                   sta{k}.fsn(tid + 1) = seq;
                               end
                               if sta{k}.msn(tid + 1) < seq && seq - sta{k}.msn(tid + 1)< thre_size 
                                   sta{k}.msn(tid + 1) = seq;
                               end
                               if sta{k}.msn(tid + 1) > seq && sta{k}.msn(tid + 1) - seq > thre_size 
                                   sta{k}.msn(tid + 1) = seq;
                               end
                               %pos = mod(seq - sta{k}.fsn(tid + 1) + tot_size,tot_size);
                               if mod(sta{k}.msn(tid + 1) - sta{k}.fsn(tid + 1) + tot_size,tot_size) > sta{k}.maxoffset(tid + 1)
                                   sta{k}.maxoffset(tid + 1) = mod(sta{k}.msn(tid + 1) - sta{k}.fsn(tid + 1) + tot_size,tot_size);
                               end
                               sta{k}.ack{tid + 1}(seq + 1) = 1; %seq序号的帧收到 wang：暂时不用偏移量设置
                           end
                        end
                        while isempty(sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame) == 0  %zhao 这里这样判断是否可行，可以考虑增加标志位  
                            frame = sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame;
                            %wang:这里计算接收时延
                            sta{k}.dl_rx_delay(tid + 1) = sta{k}.dl_rx_delay(tid + 1) + sta{k}.slot_idx - sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size) + 1).time_stamp + 10; %wang:考虑假定0.5ms的接收解码时延
                            sta{k}.dl_rx_bagnum(tid + 1) = sta{k}.dl_rx_bagnum(tid + 1) + 1;
                            sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame = '';  %清理接收缓存数组
                            sta{k}.lsn(tid + 1) = mod(sta{k}.lsn(tid + 1) + 1,tot_size);
                        end
                        %wang:从此处开始超时处理，为省时起见，可将下面这一段挪到1ms一次
                        temp_lsn = sta{k}.lsn(tid + 1);   %更新接收窗口下沿
                        count = 0;
                        %0218 zhao 超时处理位置需要改变，每个时隙处理一次即可
                        if timeout_flag(k,tid+1)
                            timeout_flag(k,tid+1) = 0;
                        while count < rx_array_size  %超时处理
                            while isempty(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1   %zhao 遍历找到最左边的缓存帧
                                temp_lsn = mod(temp_lsn + 1,tot_size);
                                count = count + 1;   %遍历一圈之后一定会跳出循环
                                if count > rx_array_size
                                    break;
                                end
                            end
                            if isempty(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1  %此时表明整个数组都空，自然不会有超时帧
                                break;
                            end
                            time_stamp = ceil(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).time_stamp / 20);
                            temp_ms = ceil(sta{k}.slot_idx/20);
                            if (temp_ms - time_stamp) > 10  %超时提交
                                sta{k}.dl_rx_delay(tid + 1) = sta{k}.dl_rx_delay(tid + 1) + sta{k}.slot_idx - sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size) + 1).time_stamp;
                                sta{k}.dl_rx_bagnum(tid + 1) = sta{k}.dl_rx_bagnum(tid + 1) + 1;
                                frame = sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame;
                                sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame = '';
                                temp_lsn = mod(temp_lsn + 1,tot_size);
                                count = count + 1;
                                sta{k}.lsn(tid + 1) = temp_lsn; %更新lsn
                                fprintf('uid %d lsn : %d has been changed in over-time submit\n',sta{k}.uid,sta{k}.lsn(tid + 1));
                            else  %此时表明lsn之后的第一个帧没有超时，即此时不存在超时帧，直接跳出超时处理
                                break;
                            end
                        end
                        end
                    elseif strcmp(mac_config.FrameType,'UpARQ')
%                         fprintf('STA %d has received UpARQ in ELLChannel,sidx = %d\n',mac_config.Uid,handles.slot_idx);
                        fb_info = mac_config.ARQConfig.fb_info;%获取ARQ帧的反馈信息，解包函数能解到多细粒度的字段还需协商，这里假定能拿到一个fb_info数组
                        uid = mac_config.Uid;  
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
                                            if fb_unit(seq + 2) == 1  %正确接收
                                                 ack_bitmap(temp_ack + 1) = 1;
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
                            %假定一个fb_info描述完一个tid队列
                            while ~sta{k}.backup_queue(tid + 1).isempty()  %backup_queue表示还未确认的包
                                pkt_info = sta{k}.backup_queue(tid + 1).front();  %先查看队列首包，但不取出
                                frame = pkt_info.frame;
                                [mac_config,~, ~] = qbandMPDUDecode(frame, 'DataFormat', 'Octets');
                                seq = mac_config.Seq;
                                time_stamp = ceil(pkt_info.time_stamp/20);
                                temp_time = ceil(sta{k}.slot_idx/20);
                                if mod((temp_time - time_stamp + 10),10) > 1 %假定在发出包后的下1ms总能收到ARQ  %wang:暂时改为不在1ms后收到ARQ就跳出
                                    fprintf('(sz)error receive the ul_arq delay\n');
                                    break;
                                end
                                if mod((temp_time - time_stamp + 10),10) ~= 1 && mod((temp_time - time_stamp + 10),10) ~= 2    %假定在发出包后的下1ms总能收到ARQ,第一次的ARQ会在2ms后收到
                                    break;
                                end
                                if mod((seq - lsn + tot_size),tot_size) < thre_size && ack_bitmap(seq + 1) == 0    %lsn需要在ARQ帧获取
                                    pkt_info = sta{k}.backup_queue(tid + 1).pop();
                                    frame = pkt_info.frame; 
                                    sta{k}.retry_queue(tid + 1).push(frame);  %把包放入重传队列
                                    sta{k}.mcs_update_info(tid + 1) = notify_tx_failed_update(sta{k}.mcs_update_info(tid + 1));
%                                      fprintf('(sz) retry the ul_packet uid : %d, seq : %d,sidx: %d\n', uid, seq,sta{k}.slot_idx);
                                else
                                    sta{k}.mcs_update_info(tid + 1) = notify_tx_succ_update(sta{k}.mcs_update_info(tid + 1));
                                    sta{k}.backup_queue(tid + 1).pop();
                                end
                            end
                            sta{k}.mcs_update_info(tid + 1) = notify_mcs_update(sta{k}.mcs_update_info(tid + 1),sta{k}.slot_idx);  %每次收到ARQ，可以进行MCS的调整
                        end  %这里已经解完所有包 
                    end
                end
            end
        end 
    end
    if flag_ell == 0  %若当前取出帧没被接收，又放回队列
        channel_ell.phy_queue.push(Baledframe_ell);  
    end
end
%%%%%%%%%%%%%%%%%%%接收普通信道%%%%%%%%%%%%%%%%%%%%
for channel_idx = 1 : numel(channel)
    queue_size = channel{channel_idx}.phy_queue.size(); %wang：为了接口方便，暂时还是在最外层遍历信道(懒得改了)
    count_dl = 0;
    for num = 1:queue_size  %wang:数据接收处理有问题,
        baled_frame = channel{channel_idx}.phy_queue.pop();
        flag = 0;  %表示当前该帧是否被sta接收的标志
        for k = 1 : numel(sta)
            if sta{k}.dl_slot_states(mod(sta{k}.slot_idx - 1, 200) + 1) == 261 && sta{k}.dl_channel == channel_idx  %RX
                [sub_A_mpdu, MU_list, ~] = qbandBaledFrameDecode(baled_frame,'DataFormat','Octets');         
                frame_num = numel(sub_A_mpdu);
                if frame_num == 0  %此时表示接收帧未打捆
                    frame_num = 1;
                    sub_A_mpdu{1} = baled_frame;
                end
                %order_frame = cell(1,size);
                for m = 1:frame_num
                    [mpdu_list,~, ~,mpdulength] = AMPDUDeaggregate(sub_A_mpdu{m}, 'DataFormat', 'Octets');
                    for sub_frame_num = 1 : numel(mpdu_list) 
                        [mac_config,~, ~] = qbandMPDUDecode(mpdu_list{sub_frame_num}, 'DataFormat', 'Octets');
                        %%%%%%%%%%%%%%%%%%%%%%%接收Beacon帧%%%%%%%%%%%%%%%%%%%%%%%%%
                        if strcmp(mac_config.FrameType,'Beacon')
                            beacon_config = mac_config.BeaconConfig;
                            polling_result = beacon_config.pollingBitmap(3:42);
                            slot_idx_polling = find(polling_result == sta{k}.uid);
                            for i = 1 : numel(slot_idx_polling)
                                if sta{k}.ul_slot_states(floor((slot_idx_polling(i)-1)/4)*20+3+mod(slot_idx_polling(i)-1,4)) == 259
                                    fprintf('wang : STA %d error,sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
                                end
                                sta{k}.ul_slot_states(floor((slot_idx_polling(i)-1)/4)*20+3+mod(slot_idx_polling(i)-1,4)) = 260;
                            end
                            flag = 1;
                        end
                        %%%%%%%%%%%%%%%%%%%%%%%接收连接帧/离线帧%%%%%%%%%%%%%%%%%%%%%%%%%
                        if strcmp(mac_config.FrameType,'AssocRsp') && strcmp(mac_config.AssocRspConfig.address,sta{k}.mac_address)  %关联响应时STA还没有UID，所以需要通过mac地址进行判断
                            flag = 1;
                             fprintf('(qband) the sta : %s the uid : %d the tick : %d loop : %d\n', string(sta{k}.mac_address), mac_config.AssocRspConfig.uid, sta{k}.slot_idx, sta{k}.backoff_info.loop);
                            sta{k}.status = 1;
                            sta{k}.backoff_info.loop = 0;
                            sta{k}.backoff_info.val = 0;
                            sta{k}.uid = mac_config.AssocRspConfig.uid;
                            %用户获取自己所处在第几个信道
                            sta{k}.dl_channel = mac_config.AssocRspConfig.dl_channel;
                            sta{k}.ul_channel = mac_config.AssocRspConfig.ul_channel;
                            handles.timeout_process = delete_delay_event(handles.timeout_process, sta{k}.uid, sta{k}.mac_address, 1);  
                           for idx = 1 : 20 : 200
                           end
                        elseif strcmp(mac_config.FrameType,'OfflineRsp') && strcmp(mac_config.OfflineRspConfig.address,sta{k}.mac_address)  %下线响应回复帧
                            flag = 1;
                            fprintf('sta %d is offline\n',sta{k}.uid);
                            sta{k} = sta_mac();  %直接将sta删除  wang:此处做何处理还需斟酌，考虑重新将STA初始化？
                            %mac地址目前采用qband +　序号作为后缀的表示
                            dec_address = comm.internal.utilities.de2biBase2LeftMSB(double(k), 48);
                            hex_address = comm.internal.utilities.bi2deLeftMSB(double(reshape(dec_address, 8, [])'), 2);
                            str_address = reshape(dec2hex(hex_address,2)', 1, []);
                            mac_address = ['FDD',str_address(4:12)];
                            sta{k}.mac_address = mac_address;
                            sta{k}.slot_idx = handles.slot_idx;
                        elseif mac_config.Uid == sta{k}.uid   %该帧是发给当前用户的
                            flag = 1;
                            %%%%%%%%%%%%%%%%%%%%%%%接收数据帧%%%%%%%%%%%%%%%%%%%%%%%%%
                            if strcmp(mac_config.getType,'Data') 
                                csr = csr_table(MU_list{m}(1));
                                if rand(1) < 1 - csr  %按照误帧率模型丢帧
    %                                 fprintf('STA %d has dropped the DL_packet, seq : %d , tid : %d , sidx: %d\n', mac_config.Uid, mac_config.Seq,mac_config.Tid,sta{k}.slot_idx);
                                    continue;
                                end
                                tid = mac_config.Tid;
                                seq = mac_config.Seq;
                                sta{k}.mcs_update_info(tid + 1).throughput = sta{k}.mcs_update_info(tid + 1).throughput + mpdulength(sub_frame_num) - 22;
                                if mod(seq - sta{k}.lsn(tid + 1) + tot_size,tot_size) >= thre_size
                                    fprintf('error ,uid : %d frame seq: %d，tid: %d is out of the receive window\n',sta{k}.uid,seq,tid);
                                    count_dl = count_dl + 1;
                                    if count_dl > 10
                                        fprintf('dl_send error\n');
                                    end
                                end
                                if mod(seq - sta{k}.lsn(tid + 1) + tot_size,tot_size) < thre_size  %lsn表示每个tid的接收下沿，此时表示在接收窗口内
                                       rx_info.frame = mpdu_list{sub_frame_num};  %wang:这里记得改,已改
                                       rx_info.time_stamp = sta{k}.slot_idx;  %这里直接存储时隙号，以便计算接收时延
                                       sta{k}.rx_array(tid + 1, mod(seq,rx_array_size) + 1) = rx_info;
                                   if sta{k}.fsn(tid + 1) == -1  %当前1ms周期还没收到帧     %zhao 更新本周期的接收bitmap位图  %wang : 修改
                                       sta{k}.fsn(tid + 1) = seq;
                                       sta{k}.msn(tid + 1) = seq;
                                       sta{k}.ack{tid + 1}(seq + 1) = 1;
                                   else
                                       if sta{k}.fsn(tid + 1) > seq && sta{k}.fsn(tid + 1) - seq < thre_size  
                                           sta{k}.fsn(tid + 1) = seq;
                                       end
                                       if sta{k}.fsn(tid + 1) < seq && seq - sta{k}.fsn(tid + 1) > thre_size
                                           sta{k}.fsn(tid + 1) = seq;
                                       end
                                       if sta{k}.msn(tid + 1) < seq && seq - sta{k}.msn(tid + 1)< thre_size 
                                           sta{k}.msn(tid + 1) = seq;
                                       end
                                       if sta{k}.msn(tid + 1) > seq && sta{k}.msn(tid + 1) - seq > thre_size 
                                           sta{k}.msn(tid + 1) = seq;
                                       end
                                       if mod(sta{k}.msn(tid + 1) - sta{k}.fsn(tid + 1) + tot_size,tot_size) > sta{k}.maxoffset(tid + 1)
                                           sta{k}.maxoffset(tid + 1) = mod(sta{k}.msn(tid + 1) - sta{k}.fsn(tid + 1) + tot_size,tot_size);
                                       end
                                       sta{k}.ack{tid + 1}(seq + 1) = 1; %seq序号的帧收到 wang：暂时不用偏移量设置
                                   end
                                end
                                while isempty(sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame) == 0  %zhao 这里这样判断是否可行，可以考虑增加标志位  
                                    frame = sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame;
                                    %fprintf('(sz) submit DL_frame uid : %d seq : %d \n', mac_config.Uid, sta{k}.lsn(tid + 1));
                                    %clear frame;         %zhao 似乎无效释放，这里直接清零应该就可以了，或者存进去的时候就应该clear
                                    %wang:这里计算接收时延
                                    sta{k}.dl_rx_delay(tid + 1) = sta{k}.dl_rx_delay(tid + 1) + sta{k}.slot_idx - sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size) + 1).time_stamp + 10; %wang:考虑假定0.5ms的接收解码时延
                                    sta{k}.dl_rx_bagnum(tid + 1) = sta{k}.dl_rx_bagnum(tid + 1) + 1;
                                    sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size)+1).frame = '';  %清理接收缓存数组
                                    sta{k}.lsn(tid + 1) = mod(sta{k}.lsn(tid + 1) + 1,tot_size);
                                end
                                %wang:从此处开始超时处理，为省时起见，可将下面这一段挪到1ms一次
                                temp_lsn = sta{k}.lsn(tid + 1);   %更新接收窗口下沿
                                count = 0;
                                %0218 zhao 超时处理位置需要改变，每个时隙处理一次即可
                                if timeout_flag(k,tid+1)
                                    timeout_flag(k,tid+1) = 0;
                                while count < rx_array_size  %超时处理
                                    while isempty(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1   %zhao 遍历找到最左边的缓存帧
                                        temp_lsn = mod(temp_lsn + 1,tot_size);
                                        count = count + 1;   %遍历一圈之后一定会跳出循环
                                        if count > rx_array_size
                                            break;
                                        end
                                    end
                                    if isempty(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame) == 1  %此时表明整个数组都空，自然不会有超时帧
                                        break;
                                    end
                                    time_stamp = ceil(sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).time_stamp / 20);
                                    temp_ms = ceil(sta{k}.slot_idx/20);
                                    if (temp_ms - time_stamp) > 10  %超时提交
                                        sta{k}.dl_rx_delay(tid + 1) = sta{k}.dl_rx_delay(tid + 1) + sta{k}.slot_idx - sta{k}.rx_array(tid + 1,mod(sta{k}.lsn(tid + 1),rx_array_size) + 1).time_stamp;
                                        sta{k}.dl_rx_bagnum(tid + 1) = sta{k}.dl_rx_bagnum(tid + 1) + 1;
                                        frame = sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame;
                                        % clear frame;
                                        sta{k}.rx_array(tid + 1,mod(temp_lsn,rx_array_size)+1).frame = '';
                                        temp_lsn = mod(temp_lsn + 1,tot_size);
                                        count = count + 1;
                                        % if temp_lsn > tot_size
                                        %    temp_lsn = temp_lsn - tot_size; 
                                        % end
                                        sta{k}.lsn(tid + 1) = temp_lsn; %更新lsn
                                        fprintf('uid %d lsn : %d has been changed in over-time submit\n',sta{k}.uid,sta{k}.lsn(tid + 1));
                                    else  %此时表明lsn之后的第一个帧没有超时，即此时不存在超时帧，直接跳出超时处理
                                        break;
                                    end
                                end
                                end
                            else
                                %%%%%%%%%%%%%%%%%%%%%%%接收DownIE帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                if strcmp(mac_config.FrameType,'DownIE')  %下行调度IE
                                    ie_config = mac_config.IEConfig;  
                                    idx1 = ie_config.idx1;
                                    idx2 = ie_config.idx2;
                                    dur1 = ie_config.dur1;
                                    dur2 = ie_config.dur2;
        %                                channel_num = ie_config.channelNumbers;
        %                                sta{k}.dl_resv_info = channel_num; %暂时将信道个数信息直接存到下行预留信息内
                                    temp_ms = mod(ceil(sta{k}.slot_idx/20), 10);
                                    fprintf('STA %d received DownIE frame,sidx = %d,idx1 = %d,dur1 = %d\n',sta{k}.uid,sta{k}.slot_idx,idx1,dur1);
                                    if dur1 > 0
                                        start_time1 = mod((temp_ms)*20 + idx1, 200);
                                        sta{k}.dl_slot_states(start_time1:start_time1+dur1-1) = 261;  %将用户这两个时隙内的状态置为接收
                                    end
                                    if dur2 > 0
                                        start_time2 = mod((temp_ms+1)*20 + idx2, 200);
                                        sta{k}.dl_slot_states(start_time2:start_time2+dur2-1) = 261;
                                    end
                                %%%%%%%%%%%%%%%%%%%%%%%接收UpIE1帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                elseif strcmp(mac_config.FrameType,'UpIE1')  %指示数据帧
                                     ie_config = mac_config.IEConfig;  
                                     idx1 = ie_config.idx1;
                                     idx2 = ie_config.idx2;
                                     dur1 = ie_config.dur1;
                                     dur2 = ie_config.dur2;
                                     temp_ms = mod(ceil(sta{k}.slot_idx/20), 10);
                                     fprintf('STA %d received UpIE1 frame,sidx = %d,idx1 = %d,dur1 = %d\n',sta{k}.uid,sta{k}.slot_idx,idx1,dur1);
                                  %  fprintf('UL_time = %d,sidx = %d\n',dur1,sta{k}.slot_idx);
        %                              if dur1 > 0 && idx1 < 19
        %                                  start_time1 = temp_ms * 20 + idx1;  %wang:上行调度代码里start_slot可能为20，考虑到temp_ms范围，应该不用对200取模
        %                                  if mod(start_time1 + dur1 - 1,20) < 19
        %                                     sta{k}.ul_slot_states(start_time1:start_time1+dur1 - 1) = 258;  %将用户这两个时隙内的状态置为接收 %wang:暂时不允许STA在1ms的后两个时隙发包
        %                                  else
        %                                      sta{k}.ul_slot_states(start_time1:temp_ms * 20 + 18) = 258;
        %                                  end
        %                              end
                                     if dur1 > 0
                                         start_time1 = temp_ms * 20 + idx1;
                                         sta{k}.ul_slot_states(start_time1:start_time1+dur1 - 1) = 258; 
                                     end
                                     if dur2 > 0
                                         start_time2 = mod((temp_ms + 1),10)*20 + idx2;
                                         sta{k}.ul_slot_states(start_time2:start_time2+dur2 - 1) = 258;
                                     end
                                %%%%%%%%%%%%%%%%%%%%%%%接收UpIE2帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                elseif strcmp(mac_config.FrameType,'UpIE2')  %指示控制帧
                                    ie_config = mac_config.IEConfig;  
                                    idx1 = ie_config.idx1;
                                    idx2 = ie_config.idx2;
                                    dur1 = ie_config.dur1;
                                    dur2 = ie_config.dur2;
                                    temp_ms = mod(ceil(sta{k}.slot_idx/20), 10);
                                    fprintf('STA %d received UpIE2 frame,sidx = %d,idx1 = %d,dur1 = %d\n',sta{k}.uid,sta{k}.slot_idx,idx1,dur1);
                                    if dur1 > 0
                                         start_time1 = temp_ms * 20 + idx1;  %wang:上行调度代码里start_slot可能为20，考虑到temp_ms范围，应该不用对200取模
                                         sta{k}.ul_slot_states(start_time1:start_time1+dur1 - 1) = 259;  %将用户这两个时隙内的状态置为接收
    
                                     end
                                     if dur2 > 0
                                         start_time2 = mod((temp_ms + 1),10)*20 + idx2;
                                         sta{k}.ul_slot_states(start_time2:start_time2+dur2 - 1) = 259;
                                     end
                                %%%%%%%%%%%%%%%%%%%%%%%接收UpARQ帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                elseif strcmp(mac_config.FrameType,'UpARQ')  %上行ARQ
    %                                 fprintf('STA %d has received UpARQ from AP ,sidx = %d\n',mac_config.Uid,sta{k}.slot_idx);
                                    fb_info = mac_config.ARQConfig.fb_info;%获取ARQ帧的反馈信息，解包函数能解到多细粒度的字段还需协商，这里假定能拿到一个fb_info数组
                                    uid = mac_config.Uid;  
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
                                        if fsn >= 0
                                            ack_bitmap(fsn + 1) = 1;  %fsn总表示收到的帧 
                                        end
                                        for l = 1:unit_num
                                            fb_unit = fb_info{n}(64+(l-1)*32+1:64+(l-1)*32+32);
                                            unit_type = comm.internal.utilities.bi2deRightMSB(fb_unit(1:2), 2);
                                            switch unit_type
                                                case 0
                                                    for seq = 1:30
                                                        temp_ack = mod(temp_ack + 1,tot_size);
                                                        if fb_unit(seq + 2) == 1  %正确接收
                                                             ack_bitmap(temp_ack + 1) = 1;
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
                                        %假定一个fb_info描述完一个tid队列
                                        while ~sta{k}.backup_queue(tid + 1).isempty()  %backup_queue表示还未确认的包
                                            pkt_info = sta{k}.backup_queue(tid + 1).front();  %先查看队列首包，但不取出
                                            frame = pkt_info.frame;
                                            [mac_config,~, ~] = qbandMPDUDecode(frame, 'DataFormat', 'Octets');
                                            seq = mac_config.Seq;
                                            time_stamp = ceil(pkt_info.time_stamp/20);
                                            temp_time = ceil(sta{k}.slot_idx/20);
                                            if mod((temp_time - time_stamp + 10),10) > 1 %假定在发出包后的下1ms总能收到ARQ  %wang:暂时改为不在1ms后收到ARQ就跳出
                                                fprintf('(sz)STA %d error receive the ul_arq delay Tid %d \n',sta{k}.uid,tid);
                                                break;
                                            end
                                            if mod((temp_time - time_stamp + 10),10) ~= 1 && mod((temp_time - time_stamp + 10),10) ~= 2    %假定在发出包后的下1ms总能收到ARQ,第一次的ARQ会在2ms后收到
                                                break;
                                            end
                                            if mod((seq - lsn + tot_size),tot_size) < thre_size && ack_bitmap(seq + 1) == 0    %lsn需要在ARQ帧获取
                                                pkt_info = sta{k}.backup_queue(tid + 1).pop();
                                                frame = pkt_info.frame; 
                                                sta{k}.retry_queue(tid + 1).push(frame);  %把包放入重传队列
                                                sta{k}.mcs_update_info(tid + 1) = notify_tx_failed_update(sta{k}.mcs_update_info(tid + 1));
    %                                             fprintf('STA will retry the ul_packet uid : %d, seq : %d,tid : %d,sidx: %d\n', uid, seq,tid,sta{k}.slot_idx);
                                            else
                                                sta{k}.mcs_update_info(tid + 1) = notify_tx_succ_update(sta{k}.mcs_update_info(tid + 1));
                                                sta{k}.backup_queue(tid + 1).pop();
                                            end
                                        end
                                        sta{k}.mcs_update_info(tid + 1) = notify_mcs_update(sta{k}.mcs_update_info(tid + 1),sta{k}.slot_idx);  %每次收到ARQ，可以进行MCS的调整
                                    end  %这里已经解完所有包  
                                %%%%%%%%%%%%%%%%%%%%%%%接收PreCon_UpRsp帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                elseif strcmp(mac_config.FrameType,'PreCon_UpRsp')    %上行时隙预留响应帧
                                    if ~mac_config.PreConditionConfig.Status
                                       sta{k}.ul_resv_info.Interval = mac_config.PreConditionConfig.Interval;
                                       sta{k}.ul_resv_info.Time_Index = mac_config.PreConditionConfig.Time_Index;
                                       sta{k}.ul_resv_info.Slot_Index = mac_config.PreConditionConfig.Slot_Index;
                                       sta{k}.ul_resv_info.Slot_Num = mac_config.PreConditionConfig.Slot_Num;
                                       sta{k}.ul_resv_info.Cycles_Num = mac_config.PreConditionConfig.Cycles_Num;
                                       fprintf('STA %d has received PreCon_UpRsp，sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
        %                                sta{k}.ul_resv_info.control_flags = true;% 添加标志位
                                    else
                                       sta{k}.ul_resv_info.Interval = mac_config.PreConditionConfig.Interval;
                                       sta{k}.ul_resv_info.Slot_Num = mac_config.PreConditionConfig.Slot_Num;
                                       sta{k}.ul_resv_info.control_flags = false;% 添加标志位
                                    end
                                %%%%%%%%%%%%%%%%%%%%%%%接收PreCon_UpRsp帧%%%%%%%%%%%%%%%%%%%%%%%%%
                                elseif strcmp(mac_config.FrameType,'PreCon_DownReq')    %下行预留请求帧
                                    sta{k}.dl_resv_info.Interval = mac_config.PreConditionConfig.Interval;
                                    sta{k}.dl_resv_info.Time_Index = mac_config.PreConditionConfig.Time_Index;
                                    sta{k}.dl_resv_info.Slot_Index = mac_config.PreConditionConfig.Slot_Index;
                                    sta{k}.dl_resv_info.Slot_Num = mac_config.PreConditionConfig.Slot_Num;
                                    sta{k}.dl_resv_info.Cycles_Num = mac_config.PreConditionConfig.Cycles_Num;
                                    fprintf('STA %d has received PreCon_DownReq from AP,sidx: %d\n',sta{k}.uid,handles.slot_idx);
                                    %%构造ack入control队列%%
                                    ackframecfg = QbandFrameConfig;
                                    ackframecfg.FrameType = 'ACK';
                                    ackframecfg.Uid = sta{k}.uid;
                                    ackframe = QbandGenerateMPDU([],ackframecfg);
                                    sta{k}.control_queue.push(ackframe);
                                    fprintf('STA %d has sent ACK to AP,sidx: %d\n',sta{k}.uid,handles.slot_idx);
                                %%%%%%%%%%%%%%%%%%%%%%%接收PreChal_Rsp帧%%%%%%%%%%%%%%%%%%%%%%%%%   
                                elseif strcmp(mac_config.FrameType,'PreChal_Rsp')       %信道预留响应帧
                                    fprintf('STA %d has received PreChal_Rsp from AP,sidx = %d\n',mac_config.Uid,sta{k}.slot_idx);
                                    status_ell = mac_config.PreChannelConfig.Status;
                                    ulchannel = mac_config.PreChannelConfig.UlChannel;
                                    dlchannel = mac_config.PreChannelConfig.DlChannel;
                                    if status_ell && dlchannel ~= 0
                                        sta{k}.Reqflag_Downchannel = 2;                     %允许低时延下行通信
                                    end
                                    if status_ell && ulchannel ~= 0
                                        sta{k}.Reqflag_Upchannel = 2;                     %允许低时延上行通信
                                    end
                                elseif strcmp(mac_config.FrameType,'ChannelReq')
                                    fprintf('STA %d has received Channel_Req from AP,sidx = %d\n',mac_config.Uid,sta{k}.slot_idx);
                                    dl_channel = mac_config.ChannelReqConfig.down_channel;
                                    ul_channel = mac_config.ChannelReqConfig.up_channel;
                                    sta{k}.dl_channel = dl_channel;     %更新该用户信道信息
                                    sta{k}.ul_channel = ul_channel;
                                end
                            end
                        end
                    end  
                end
            end
    
        end
        if flag == 0  %若当前取出帧没被接收，又放回队列
            channel{channel_idx}.phy_queue.push(baled_frame);  
        end
    end
end
%%%%%%%%%%%%每ms最后一个时隙构造DownARQ%%%%%%%%%%%%%
for k = 1 : numel(sta)
    if isempty(sta{k})
        continue;
    end
    if sta{k}.status == 1 && mod(sta{k}.slot_idx,20) == 0
        mac_config.FrameType = 'DownARQ';
        mac_config.Uid = sta{k}.uid;  %这里uid的填入还需斟酌
%       ac_config.transID = sta{k}.transID;    %在sta类对象中维护transID字段表示当前控制帧的序号
%       sta{k}.transID = mod(sta{k}.transID + 1,2^8);
        tid_num = 0;
        fb_info = [];
        for m = 1:8  %ARQ帧的组帧函数接口需要确认
            if sta{k}.fsn(m) ~= -1  %wang：在这里对ack做处理
                %ack{m} = 
                offset_bitmap = zeros(1,sta{k}.maxoffset(m));
                for p = 1:sta{k}.maxoffset(m)  %wang:此处有问题，原因不明
                    if mod(sta{k}.fsn(m) + p,tot_size) + 1 <= numel(sta{k}.ack{m}) %越界判断 wang:为什么会出现越界原因未知，这样修改测试后暂时未发现问题
                        offset_bitmap(p) = sta{k}.ack{m}(mod(sta{k}.fsn(m) + p,tot_size) + 1);
                    end
                end
                temp_ack = 1;
                tid_num = tid_num + 1;
                fb_info(tid_num).unit_num = ceil(sta{k}.maxoffset(m)/30); %ack数组中对应tid的确认数组的大小就是确认的帧数量，目前暂时只构造Bitmap确认的帧
                fb_info(tid_num).tid = m - 1;
                fb_info(tid_num).fsn = sta{k}.fsn(m);
  %              fprintf('fsn : %d,sidx : %d\n', sta{k}.fsn(m),sta{k}.slot_idx);
                fb_info(tid_num).size = sta{k}.maxoffset(m);
                if sta{k}.maxoffset(m) > 5000
                    fprintf('error,arq frame is too large\n');
                    fprintf('fsn = %d\n',sta{k}.fsn(m));
                    fprintf('msn = %d\n',sta{k}.msn(m));
                end
                fb_info(tid_num).lsn = sta{k}.lsn(m); %在ARQ帧中增加lsn字段
       %         fprintf('lsn: %d\n',sta{k}.lsn(m));
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
            end
        end
            
        %zhao 先在外面构造payload，后面考虑将payload的构造和解析移到对应的ARQ的构造和解析函数中
        if ~isempty(fb_info)
            fb_payload = cell(1,numel(fb_info));
            for m = 1 : numel(fb_info)
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
%             fprintf('STA %d has created ARQ frame,sidx = %d\n',sta{k}.uid,sta{k}.slot_idx);
            mac_config = QbandFrameConfig;
            mac_config.FrameType = 'DownARQ';
            mac_config.Uid = sta{k}.uid;
            arq_config = ARQConfig;
            arq_config.tidNum = tid_num;
            arq_config.fb_info = fb_payload;
            mac_config.ARQConfig = arq_config;
            arq_frame = QbandGenerateMPDU([], mac_config);
%             if size(arq_frame,1) > 5000  %wang:为什么报错 ？？？？
%                 fprintf('arq frame is too large\n');
%             end
            sta{k}.control_queue.push(arq_frame);%将ARQ帧入队
        end
    end
end
handles.stas = sta;
handles.dl_channel = channel;





