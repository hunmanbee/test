%% ==================== run_ablation_study.m（健壮版） ====================
clc; clear; close all;

experiments = {
    {'RL',        'full',         ''},
    {'RL',        'no_fairness',  ''},
    {'RL',        'no_diversity', ''},
    {'DQN',       'full',         ''},
    {'Baseline',  'full',         'fixed'},
    {'Baseline',  'full',         'roundrobin'},
    {'Baseline',  'full',         'greedy'}
};

num_runs = 3;           % 先跑3轮测试，稳定后再改回5
sta_num = 4;
simulation_time = 2;

summary = table();

for i = 1:size(experiments, 1)
    sim_mode    = experiments{i}{1};
    abl_mode    = experiments{i}{2};
    base_method = experiments{i}{3};
    
    if strcmpi(sim_mode, 'Baseline')
        exp_name = sprintf('%s + %s', sim_mode, base_method);
    elseif strcmpi(sim_mode, 'DQN')
        exp_name = 'DQN';
    else
        exp_name = sprintf('%s + %s', sim_mode, abl_mode);
    end
    
    fprintf('\n========== 第 %d/7 组: %s ==========\n', i, exp_name);
    
    rewards = []; usages = []; fairnesss = []; delays = [];
    
    for r = 1:num_runs
        fprintf('  第 %d 轮运行中...\n', r);
        
        try
            res = startSimulation(sim_mode, abl_mode, base_method, sta_num, simulation_time);
            
            rewards(end+1)   = res.mean_reward;
            usages(end+1)    = res.mean_usage;
            fairnesss(end+1) = res.jain_fairness;
            delays(end+1)    = res.mean_delay;
            
            fprintf('    完成！mean_reward = %.2f\n', res.mean_reward);
            
        catch ME
            fprintf('    【错误】第 %d 组 第 %d 轮失败: %s\n', i, r, ME.message);
            continue;   % 跳过这一轮，继续跑下一轮
        end
    end
    
    if ~isempty(rewards)
        new_row = table({exp_name}, mean(rewards), std(rewards), ...
                        mean(usages), mean(fairnesss), mean(delays), ...
            'VariableNames', {'Experiment', 'MeanReward', 'StdReward', ...
                              'MeanUsage', 'MeanFairness', 'MeanDelay'});
        summary = [summary; new_row];
    end
end

disp(summary);
writetable(summary, 'results/ablation_7groups.csv');
save('results/ablation_7groups.mat', 'summary');

plot_ablation_figures();

% 
% test = startSimulation('DQN', 'full', 4, 2);