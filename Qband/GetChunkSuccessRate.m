function csr = GetChunkSuccessRate (mode,snr, nbits) 
%       load const_value
      WIFI_CODE_RATE_1_2 = 3;
      WIFI_CODE_RATE_2_3 = 2;
      WIFI_CODE_RATE_3_4 = 1;
      WIFI_CODE_RATE_5_6 = 4;
      if (mode.constellation_size== 2)
          if (mode.code_rate == WIFI_CODE_RATE_1_2)
              csr = GetFecBpskBer (snr,nbits,1); 
              return;
          else
              csr = GetFecBpskBer (snr,nbits,3);
              return;
          end
       elseif (mode.constellation_size == 4)
          if (mode.code_rate == WIFI_CODE_RATE_1_2)
              csr = GetFecQpskBer (snr,nbits,1); 
              return;
          else
              csr = GetFecQpskBer (snr,nbits,3); 
              return;
          end
      elseif (mode.constellation_size == 16)
          if (mode.code_rate == WIFI_CODE_RATE_1_2)
              csr = GetFec16QamBer (snr,nbits,1);
              return;
          else
              csr = GetFec16QamBer (snr,nbits,3);
              return;
          end
      elseif (mode.constellation_size == 64)
          if (mode.code_rate == WIFI_CODE_RATE_1_2)
              csr = GetFec64QamBer (snr,nbits,1); 
              return;
          elseif (mode.code_rate == WIFI_CODE_RATE_2_3)
              csr = GetFec64QamBer (snr,nbits,2); 
              return;
          elseif (mode.code_rate == WIFI_CODE_RATE_3_4)
              csr = GetFec64QamBer (snr,nbits,3); 
              return;
          elseif (mode.code_rate () == WIFI_CODE_RATE_5_6)
              csr = GetFec64QamBer (snr,nbits,5);
              return;
          else
              csr = GetFec64QamBer (snr,nbits,3); 
              return;
          end
      end
  return;
 end

function ber = Get64QamBer (snr)
  z = sqrt (snr / (21.0 * 2.0));
  ber = 7.0 / 12.0 * 0.5 * erfc (z);
end

function ber = Get16QamBer (snr)
  z = sqrt (snr / (5.0 * 2.0));
  ber = 0.75 * 0.5 * erfc (z);
end

function ber = GetQpskBer (snr)
   z = sqrt (snr / 2.0);
   ber = 0.5 * erfc (z);
end

function ber = GetBpskBer (snr)
   z = sqrt (snr);
   ber = 0.5 * erfc (z);
end

function pms = GetFecBpskBer (snr, nbits,bValue) 
  ber = GetBpskBer (snr);
  if (ber == 0.0)
    pms = 1.0;
    return;
  end
  pe = CalculatePe (ber, bValue);
  pe = min (pe, 1.0);
  pms = power (1 - pe, nbits);
end

function pms = GetFecQpskBer (snr, nbits,bValue) 
  ber = GetQpskBer (snr);
  if (ber == 0.0)
    pms = 1.0;
    return;
  end
  pe = CalculatePe (ber, bValue);
  pe = min (pe, 1.0);
  pms = power (1 - pe, nbits);
end

function pms = GetFec16QamBer (snr, nbits,bValue) 
  ber = Get16QamBer (snr);
  if (ber == 0.0)
    pms = 1.0;
    return;
  end
  pe = CalculatePe (ber, bValue);
  pe = min (pe, 1.0);
  pms = power (1 - pe, nbits);
end


function pms = GetFec64QamBer (snr, nbits, bValue) 
  ber = Get64QamBer (snr);
  if (ber == 0.0)
      pms = 1.0;
      return;
  end
  pe = CalculatePe (ber, bValue);
  pe = min (pe, 1.0);
  pms = power (1 - pe, nbits);
end

function pe = CalculatePe (p, bValue) 
  D = sqrt (4.0 * p * (1.0 - p));
  pe = 1.0;
  if (bValue == 1)
      %code rate 1/2, use table 3.1.1
      pe = 0.5 * (36.0 * power (D, 10) ...,
                  + 211.0 * power (D, 12) ...,
                  + 1404.0 * power (D, 14) ...,
                  + 11633.0 * power (D, 16) ...,
                  + 77433.0 * power (D, 18) ...,
                  + 502690.0 * power (D, 20) ...,
                  + 3322763.0 * power (D, 22) ...,
                  + 21292910.0 * power (D, 24) ...,
                  + 134365911.0 * power (D, 26));
  elseif (bValue == 2)
      %code rate 2/3, use table 3.1.2
      pe = 1.0 / (2.0 * bValue) * ...,
        (3.0 * power (D, 6) ...,
         + 70.0 * power (D, 7) ...,
         + 285.0 * power (D, 8) ...,
         + 1276.0 * power (D, 9) ...,
         + 6160.0 * power (D, 10) ...,
         + 27128.0 * power (D, 11) ...,
         + 117019.0 * power (D, 12) ...,
         + 498860.0 * power (D, 13) ...,
         + 2103891.0 * power (D, 14) ...,
         + 8784123.0 * power (D, 15));
  elseif (bValue == 3)
      %%code rate 3/4, use table 3.1.2
      pe = 1.0 / (2.0 * bValue) * ...,
        (42.0 * power (D, 5) ...,
         + 201.0 * power (D, 6) ...,
         + 1492.0 * power (D, 7) ...,
         + 10469.0 * power (D, 8) ...,
         + 62935.0 * power (D, 9) ...,
         + 379644.0 * power (D, 10) ...,
         + 2253373.0 * power (D, 11) ...,
         + 13073811.0 * power (D, 12) ...,
         + 75152755.0 * power (D, 13) ...,
         + 428005675.0 * power (D, 14));
  elseif (bValue == 5)
      %code rate 5/6, use table V from D. Haccoun and G. Begin, "High-Rate Punctured Convolutional Codes
      %for Viterbi Sequential Decoding", IEEE Transactions on Communications, Vol. 32, Issue 3, pp.315-319.
      pe = 1.0 / (2.0 * bValue) * ...,
        (92.0 * power (D, 4.0) ...,
         + 528.0 * power (D, 5.0) ...,
         + 8694.0 * power (D, 6.0) ...,
         + 79453.0 * power (D, 7.0) ...,
         + 792114.0 * power (D, 8.0) ...,
         + 7375573.0 * power (D, 9.0) ...,
         + 67884974.0 * power (D, 10.0) ...,
         + 610875423.0 * power (D, 11.0) ...,
         + 5427275376.0 * power (D, 12.0) ...,
         + 47664215639.0 * power (D, 13.0));
   else
       error('(sz) CalculatePe: error bvalue');  
   end
end

