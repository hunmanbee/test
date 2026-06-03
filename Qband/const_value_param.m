WIFI_CODE_RATE_UNDEFINED = 0;
WIFI_CODE_RATE_3_4 = 1;
WIFI_CODE_RATE_2_3 = 2;
WIFI_CODE_RATE_1_2 = 3;
WIFI_CODE_RATE_5_6 = 4;
  
% STA状态定义
UNCONNECT = 0;
AWAKE     = 1;
SLEEP     = 2;

% 时隙状态定义
BEACON_TX     = 257;
UL_DATA_TX    = 258;
CONTROL_TX    = 259;
POLLING_TX    = 260;
RX            = 261;
IDLE          = 262;
RANDOM_ACCESS = 263;
NOT_DEFINED   = 265;

%MCS等级调整相关参数
PER_LOW = 0.03;
PER_HIGH = 0.1;
MAX_MCS_VALUE = 8;
MCS_INCREASE_TIME_TICK = 200;
MCS_DECREASE_TIME_TICK = 60;  
MCS_DECREASE_PACKET_NUM_THRESHOLD = 200;  
fc = 42e9;
dist = 5;
powerLevel = 15;
txGain = 10;
save const_value