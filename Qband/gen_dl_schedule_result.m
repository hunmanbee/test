function dl_result = gen_dl_schedule_result(ap_mac,mcs_table,channel)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%输入：ap_mac对象
%输出：表征时隙的分配 dl_result结构体
% 含有：用户号  uid  
%       开始时隙  Start_slot
%       分配时隙数 Slot_num
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Priority = 10; %tid序列的优先级，1表示10，2表示20
dl_result = cell(1,4); %初始化，否则会报错
%获取每个下行信道的用户数量
for i = 1 : 4
    stas_num(i) = numel(ap_mac.dl_channel_info{i});
end
for i = 1 : 4
    channel_width(i) = channel{i}.bandwith;
end
for m = 1 : 4
    %获取该信道中的用户数据
    for i = 1 :stas_num(m)
        stas_info(i) = ap_mac.stas_info(ap_mac.get_index(ap_mac.dl_channel_info{m}(i)));
    end
    for i=1:stas_num(m)   %计算权重和下行流量
        weight = 0;
        sum_dl_bytes = 0;
        if stas_info(i).dl_resv_info.Slot_Num == 0 && stas_info(i).control_flags_DownChal == 0    %下行数据排除已预留(包括低时延信道)的用户
            for j =1:8
                weight = weight + stas_info(i).dl_tx_info(j).pkt_bytes+...
                    stas_info(i).dl_tx_info(j).pkt_num*j*Priority;
                sum_dl_bytes = sum_dl_bytes+stas_info(i).dl_tx_info(j).pkt_bytes;
            end
        else
            weight = 0;
            sum_dl_bytes = 0; 
        end
        stas_weight(i).uid = stas_info(i).sta_id;
        stas_weight(i).weight = weight;
        stas_weight(i).sum_bytes = sum_dl_bytes;
    end
    %zhao 后续可以考虑利用堆排优化
    for i=1:stas_num(m)-1  %权重排序
        for j=i+1:stas_num(m)
            if(stas_weight(i).weight<stas_weight(j).weight)
                temp  = stas_weight(i);
                stas_weight(i) = stas_weight(j);
                stas_weight(j) = temp;
            end
        end
    end
    %判断是否是beacon帧， 
    tag = mod(ap_mac.slot_idx,200);
    if(tag>180&&tag<201)
        start_slot = 3;
    else
        start_slot = 1;
    end
    %统计下ms已预留的下行时隙数目
    PreCon_Num = 0;
    temp_ms = mod(ceil(ap_mac.slot_idx/20), 10); 
    for i = 1 : stas_num(m)
        if (temp_ms == 0 && stas_info(i).dl_resv_info.Slot_Num ~= 0) || stas_info(i).control_flags_Down == 3
            if mod(temp_ms + 1 - stas_info(i).dl_resv_info.Time_Index , stas_info(i).dl_resv_info.Interval) == 0
                PreCon_Num = PreCon_Num + stas_info(i).dl_resv_info.Slot_Num;
            end
        end
    end
    
    for i=1:stas_num(m)          %分配时隙
        if stas_weight(i).sum_bytes == 0
            break;
        end
        dl_result{m}(i).uid = stas_weight(i).uid;
        dl_result{m}(i).Start_slot = start_slot;
        index = ap_mac.get_index(dl_result{m}(i).uid);
        dl_result{m}(i).Slot_num = 0;
        for tid = 0 : 7
            Speed = mcs_table.table_elem(ap_mac.stas_info(index).mcs_update_info(tid + 1).mcs_val).data_rate * 1e6 * channel_width(m) / 540 / 8 * 5e-5; %此处速率的计算在有信道预留时需要修改
            dl_result{m}(i).Slot_num = dl_result{m}(i).Slot_num + ap_mac.stas_info(index).dl_tx_info(tid + 1).pkt_bytes / Speed;
        end
        dl_result{m}(i).Slot_num = ceil(dl_result{m}(i).Slot_num);
        start_slot = start_slot + dl_result{m}(i).Slot_num;
        if(start_slot >= 19 - PreCon_Num)
            dl_result{m}(i).Slot_num = 19 - PreCon_Num -dl_result{m}(i).Start_slot;
    %         for k = i : stas_num - 1
    %             fprintf('sta %d will not be schedule in DlChannel\n',stas_weight(k).uid);
    %         end
            break;
        end
    end
    for k = 1 : numel(dl_result{m})
        if dl_result{m}(k).Slot_num + dl_result{m}(k).Start_slot > 19 - PreCon_Num
            dl_result{m}(k).Slot_num = 19 - PreCon_Num - dl_result{m}(k).Start_slot;
        end
    end
end


