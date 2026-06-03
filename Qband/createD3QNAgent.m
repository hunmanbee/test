function agent = createD3QNAgent(env)
    obsInfo = getObservationInfo(env);
    actInfo = getActionInfo(env);
    numActions = length(actInfo.Elements);
    
    fprintf('观测维度: %d  动作数量: %d\n', obsInfo.Dimension(1), numActions);

    % ========== 简化网络（2层隐藏层，神经元减半）==========
    network = [
        featureInputLayer(obsInfo.Dimension(1), 'Name', 'state')
        fullyConnectedLayer(32, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(16, 'Name', 'fc2')
        reluLayer('Name', 'relu2')
        fullyConnectedLayer(numActions, 'Name', 'output')
    ];

    dqnet = dlnetwork(network);

    qFunction = rlVectorQValueFunction(dqnet, obsInfo, actInfo, ...
        'ObservationInputNames', {'state'});

    % 优化器：降低学习率，减小梯度裁剪
    criticOpts = rlOptimizerOptions(...
        'LearnRate', 3e-5, ...           % 降低学习率，更稳定
        'GradientThreshold', 1.0, ...    % 减小梯度裁剪阈值
        'Optimizer', 'adam');

    agentOpts = rlDQNAgentOptions(...
        'UseDoubleDQN', true, ...
        'TargetSmoothFactor', 1e-2, ...   % 目标网络更新稍快
        'TargetUpdateFrequency', 400, ... % 降低更新频率，更稳定
        'ExperienceBufferLength', 20000, ...
        'MiniBatchSize', 32, ...          % 减小批量大小，适应小样本
        'DiscountFactor', 0.9, ...       % 减小折扣因子，更关注近期奖励
        'CriticOptimizerOptions', criticOpts);

    % Epsilon 衰减：初始高探索，在 500 步左右降到 0.1
    agentOpts.EpsilonGreedyExploration.Epsilon     = 0.95;  % 初始探索率 95%
    agentOpts.EpsilonGreedyExploration.EpsilonMin  = 0.05;  % 最低探索率 10%
    agentOpts.EpsilonGreedyExploration.EpsilonDecay = 0.005;  % 每步衰减 0.005%，约 500 步后到 0.1


    agent = rlDQNAgent(qFunction, agentOpts);

    fprintf('优化后 DQN Agent 创建成功！(网络 64→32，动作数 %d)\n', numActions);
end