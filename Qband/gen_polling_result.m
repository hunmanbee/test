function [polling_result,polling_idx] = gen_polling_result(ap_mac)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%输入：ap_mac类对象
%输出：大小为40的polling_result{n}数组,最后轮询到的用户索引polling_idx
%polling_result{n}数组指示：10ms的polling用户uid，每1ms至多分配4个时隙，将分配的用户uid填入对应的数组位置
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% stas_num(n) = ap_mac.sta_num;
%获取每个上行信道的用户数量
for i = 1 : 4
    stas_num(i) = numel(ap_mac.ul_channel_info{i});
end
%获取每个信道开始轮询的用户对应的索引
for i = 1 : 4
    start_idx(i) = ap_mac.polling_idx(i) + 1;
end
% start_idx(n)= ap_mac.polling_idx + 1;
PHY_speed = 200000000 / 1000 / 8;  %1Gbps
BSR_threshold1 = PHY_speed*0.05;  %一个时隙的数据量
BSR_threshold2 = PHY_speed*0.1;%两个时隙的数据量
BSR_threshold3 = PHY_speed*0.15;%三个时隙的数据量
for i = 1 : 4
    polling_result{i} = ones(1,40)*256;
end
polling_idx = zeros(1,4);

for n = 1 : 4
    if(numel(ap_mac.ul_channel_info{n}) ~= 0) %当前上行信道存在使用用户
        if(stas_num(n)>40)% 每ms轮询四个用户
            polling_idx(n) = mod(start_idx(n)+39,stas_num(n));
            for i=1:40
                idx_u = start_idx(n)+i-1;
                if(idx_u>stas_num(n))%ap的用户轮询完一遍，重新从第一个开始
                    idx_u = 1;
                    start_idx(n) = start_idx(n)-stas_num(n);
                end
                polling_result{n}(i) = ap_mac.ul_channel_info{n}(idx_u);
            end
        else
            if(stas_num(n)>20)%每ms轮询两个用户
                polling_idx(n) = mod(start_idx(n)+19,stas_num(n));
                for i=0:9

                    idx = 1+4*i;
                    idx_end = 4*(i+1);
                    idx_u1 = start_idx(n)+2*i;
                    idx_u2 = start_idx(n)+2*i+1;

                    if(idx_u1>stas_num(n))%ap的用户轮询完一遍，重新从第一个开始
                        idx_u1 = 1;
                        idx_u2 = 2;
                        start_idx(n) = start_idx(n)-stas_num(n);
                    end
                    %第一个用户
                    if(sum(ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{n}(idx_u1))).buffer_len,2)>BSR_threshold1)%分配两个时隙
                        polling_result{n}(idx:idx+1) = ap_mac.ul_channel_info{n}(idx_u1);
                        idx = idx+2;
                    else%分配一个时隙
                        polling_result{n}(idx) = ap_mac.ul_channel_info{n}(idx_u1);
                        idx = idx+1;
                    end

                    if(idx_u2>stas_num(n)) %ap的用户轮询完一遍，重新从第一个开始
                        idx_u2 = 1;
                        start_idx(n) = start_idx(n)-stas_num(n);
                    end
                    %第二个用户
                    if(sum(ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{n}(idx_u2))).buffer_len,2)>BSR_threshold1)%分配两个时隙
                        polling_result{n}(idx:idx+1) = ap_mac.ul_channel_info{n}(idx_u2);
                        idx = idx+2;
                    else  %分配一个时隙
                        polling_result{n}(idx) = ap_mac.ul_channel_info{n}(idx_u2);
                        idx = idx+1;
                    end
                    if(idx<idx_end+1)
                        polling_result{n}(idx:idx_end) = 256;
                    end
                end
            else%每ms轮询一个用户
                polling_idx(n) = mod(start_idx(n)+9,stas_num(n));
                for i=0:9

                    idx1 = 1+4*i;
                    idx2 = 2+4*i;
                    idx3 = 3+4*i;
                    idx4 = 4+4*i;
                    idx_u = start_idx(n)+i;

                    if(idx_u>stas_num(n))%ap的用户轮询完一遍，重新从第一个开始
                        idx_u = 1;
                        start_idx(n) = start_idx(n)-stas_num(n);
                    end
                    if(sum(ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{n}(idx_u))).buffer_len,2)>BSR_threshold3)%分配4个时隙
                        polling_result{n}(idx1:idx4) = ap_mac.ul_channel_info{n}(idx_u);
                    else
                        if(sum(ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{n}(idx_u))).buffer_len,2)>BSR_threshold2)%分配3个时隙
                            polling_result{n}(idx1:idx3) = ap_mac.ul_channel_info{n}(idx_u);
                            polling_result{n}(idx4) = 256;
                        else
                            if(sum(ap_mac.stas_info(ap_mac.get_index(ap_mac.ul_channel_info{n}(idx_u))).buffer_len,2) >BSR_threshold1)%分配2个时隙
                                polling_result{n}(idx1:idx2) = ap_mac.ul_channel_info{n}(idx_u);
                                polling_result{n}(idx3:idx4) = 256;
                            else   %分配一个时隙
                                polling_result{n}(idx1) = ap_mac.ul_channel_info{n}(idx_u);
                                polling_result{n}(idx2:idx4) = 256;
                            end
                        end
                    end
                end
            end
        end
    end
end