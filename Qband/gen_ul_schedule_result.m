function [ul_c_result,ul_d_result] = gen_ul_schedule_result(ap_mac,mcs_table,channel)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%输入：ap_mac对象
%输出：结构体表征时隙的分配
%      ul_c_result表示控制时隙的分配,ul_d_result表示数据时隙的分配
% 含有：用户号  uid  
%       开始时隙  start_slot
%       分配时隙数 slot_num
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Priority = 10;  %tid序列的优先级，1表示10，2表示20
% stas_num(m) = ap_mac.sta_num;
%获取每个下行信道的用户数量
for i = 1 : 4
    stas_num(i) = numel(ap_mac.dl_channel_info{i});
end
for i = 1 : 4
    channel_width(i) = channel{i}.bandwith;
end
ul_c_result = cell(1,4);
ul_d_result = cell(1,4);
for m = 1 : 4
    %计算上下行流量
    sum_ul_bytes = zeros(1,stas_num(m));
    sum_dl_bytes = zeros(1,stas_num(m));
    %获取该信道中的用户数据
    for i = 1 :stas_num(m)
        stas_info(i) = ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{m}(i)));
    end
    for i=1:stas_num(m)
        if stas_info(i).ul_resv_info.Slot_Num == 0 && stas_info(i).control_flags_UpChal == 0 % 上行数据排除已预留（包括低时延信道）的用户
            sum_ul_bytes(i) = sum(stas_info(i).buffer_len);
        else    % 若已经预留，则将对应数据量置0
            sum_ul_bytes(i) = 0;    
        end
        if stas_info(i).control_flags_UpChal == 0    %排除上行信道预留的用户
            for k=1:8   
                sum_dl_bytes(i) = sum_dl_bytes(i)+stas_info(i).dl_tx_info(k).pkt_bytes;
            end
        else
            sum_dl_bytes(i) = 0;
        end
    end

    %计算这个1ms除去用于polling时隙的开始时隙  %wang:这段测试有问题
    slot_idx = mod(ceil(mod(ap_mac.slot_idx,200)/20),10);
    polling_num = 4;
    if ~isempty(ap_mac.polling_result{m})
        for i=1:4
            if(ap_mac.polling_result{m}(i+4*slot_idx)==256)
                polling_num = i-1;
                break;
            end
        end
    end
    start_slot = 3 + polling_num; %wang : 暂时对每个STA都固定分配polling wang : 暂时修改为时隙号从7开始
    PreCon_Num = 0;
    % temp_ms = mod(mod(ap_mac.slot_idx,200)-1,20) + 1; 
    temp_ms = mod(mod(ceil(ap_mac.slot_idx/20)-1, 10) + 2,10);
    for i = 1 : stas_num(m)
        if stas_info(i).control_flags == 2
            if mod(temp_ms - stas_info(i).ul_resv_info.Time_Index , stas_info(i).ul_resv_info.Interval) == 0
                PreCon_Num = PreCon_Num + stas_info(i).ul_resv_info.Slot_Num;
            end
        end
    end
    tag = 1;
    temp_ms = mod(slot_idx - 1 + 10,10);
    control_size = 1;
    %分配上行控制时隙，优先分配在之前未能分配到控制时隙的用户
    % for i = 1 : stas_num(m)
    %     if  ~stas_info(i).getcontrolnum %表示之前（上ms）因时隙不够未能分配到控制时隙
    %         if  stas_info(i).dl_send_state(temp_ms + 1) == 1 %该ms也有下行数据，则一并分配时隙
    %             stas_info(i).dl_send_state(temp_ms + 1) = 0;
    %         end
    %         if(start_slot<=20)
    %             ul_c_result(control_size).uid = stas_info(i).sta_id;
    %             ul_c_result(control_size).start_slot = start_slot;
    %             ul_c_result(control_size).slot_num = 1;
    %             start_slot = start_slot + 1;
    %             control_size = control_size + 1;
    %             stas_info(i).getcontrolnum = true;
    %         else
    %             tag = 0;%时隙分配完，修改标志
    %             break;
    %         end
    %     end
    % end
    for i = 1 : stas_num(m)
        if  stas_info(i).dl_send_state(temp_ms + 1) == 1 %表示当前1ms该STA是否有下行流量
            stas_info(i).dl_send_state(temp_ms + 1) = 0;
             if(start_slot<=20)
                ul_c_result{m}(control_size).uid = stas_info(i).sta_id;
                ul_c_result{m}(control_size).start_slot = start_slot;
                ul_c_result{m}(control_size).slot_num = 1;
                start_slot = start_slot + 1;
                control_size = control_size + 1;
             else
                tag = 0;%时隙分配完，修改标志
%                 %遍历剩余用户，若其有下行流量则将getcontrolnum置false
%                 for j = i : stas_num(m)
%                     if stas_info(i).dl_send_state(temp_ms + 1) == 1
%                         stas_info(i).dl_send_state(temp_ms + 1) = 0;
%                         stas_info(i).getcontrolnum = false;
%                     end
%                 end
                break;
             end
        elseif stas_info(i).dl_resv_info.Slot_Num ~= 0  %有下行预留用户
             if(start_slot<=20)
                ul_c_result{m}(control_size).uid = stas_info(i).sta_id;
                ul_c_result{m}(control_size).start_slot = start_slot;
                ul_c_result{m}(control_size).slot_num = 1;
                start_slot = start_slot + 1;
                control_size = control_size + 1;
             else
                tag = 0;%时隙分配完，修改标志
%                 %遍历剩余用户，若其有下行流量则将getcontrolnum置false
%                 for j = i : stas_num(m)
%                     if stas_info(i).dl_send_state(temp_ms + 1) == 1
%                         stas_info(i).dl_send_state(temp_ms + 1) = 0;
%                         stas_info(i).getcontrolnum = false;
%                     end
%                 end
                break;
             end 
        end
    end
    %开始分配数据传输时隙，按照数据量和优先级分配
    if(tag==1) %标志还有剩余时隙
        for i=1:stas_num(m)  %计算权重
            if stas_info(i).ul_resv_info.Slot_Num == 0 % 排除已预留的用户
                idx = i;
                weight = 0;
                for j=1:8  
                    weight = weight + stas_info(idx).buffer_len(j) * j * Priority;
                end
                stas_weight(i).uid = stas_info(idx).sta_id;
                stas_weight(i).weight = weight;
                stas_weight(i).sum_bytes = sum_ul_bytes(idx);
            else    % 若为预留用户，将权重和数据量置0
                idx = i;
                stas_weight(i).uid = stas_info(idx).sta_id;
                stas_weight(i).weight = 0;
                stas_weight(i).sum_bytes = 0;
            end
        end

        for i=1:stas_num(m)-1  %权重排序
            for j=i+1:stas_num(m)
                if(stas_weight(i).weight<stas_weight(j).weight)
                    temp  = stas_weight(i);
                    stas_weight(i) = stas_weight(j);
                    stas_weight(j) = temp;
                end
            end
        end

        for i=1:stas_num(m)     %分配剩余时隙，数据量为0不分配时隙
            if(start_slot <= 20-PreCon_Num)
                ul_d_result{m}(i).uid = stas_weight(i).uid;
                ul_d_result{m}(i).start_slot = start_slot;
                index = ap_mac.get_index(ul_d_result{m}(i).uid);
                ul_d_result{m}(i).slot_num = 0;
                if index > 0 && stas_weight(i).sum_bytes ~= 0
                    for tid = 0 : 7
                        speed = mcs_table.table_elem(ap_mac.stas_info(index).ul_mcs_info(tid + 1)).data_rate * 1e6 * channel_width(m) / 540 / 8 * 5e-5;  %这里后续需要遍历各tid
                        ul_d_result{m}(i).slot_num = ul_d_result{m}(i).slot_num + ap_mac.stas_info(index).buffer_len(tid + 1) / speed;  %wang:此处计算策略待定，可考虑
                    end
                end
                ul_d_result{m}(i).slot_num = ceil(ul_d_result{m}(i).slot_num);
                start_slot = start_slot+ul_d_result{m}(i).slot_num;
            else   %所有时隙已分配完,检查最后一个时隙分配是否超出范围
                if(start_slot>21-PreCon_Num)
                    ul_d_result{m}(i-1).slot_num = 21-PreCon_Num-ul_d_result{m}(i-1).start_slot;
                end
                break;
            end
        end
        for k = 1: numel(ul_d_result{m})
            if ul_d_result{m}(k).start_slot + ul_d_result{m}(k).slot_num > 21-PreCon_Num
                ul_d_result{m}(k).slot_num = 21-PreCon_Num-ul_d_result{m}(k).start_slot;
            end
        end
    end
end



