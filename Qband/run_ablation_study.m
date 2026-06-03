%% ==================== run_ablation_study.m（方案二 + 方案三 修复版） ====================
% 修改要点：
% 1. Baseline 组不计算/记录 MeanReward（因为 baseline 本身没有 reward 概念）
% 2. 每次实验 run 成功后自动保存 per-run 数据到 results/ 目录（支持 plot_ablation_figures.m 正确绘图）
% 3. 表格中 Baseline 的 MeanReward / StdReward 显示为 NaN（更符合实际）

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

if ~exist('results', 'dir')
    mkdir('results');
end

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
            
            % ========== 关键修改：只对非 Baseline 组记录 reward ==========
            if ~strcmpi(sim_mode, 'Baseline')
                rewards(end+1)   = res.mean_reward;
            end
            usages(end+1)    = res.mean_usage;
            fairnesss(end+1) = res.jain_fairness;
            delays(end+1)    = res.mean_delay;
            
            if ~strcmpi(sim_mode, 'Baseline')
                fprintf('    完成！mean_reward = %.2f\n', res.mean_reward);
            else
                fprintf('    完成！(Baseline 无 reward 概念)\n');
            end
            
            % ========== 方案三：自动保存 per-run 数据 ==========
            run_name = sprintf('%s_run%d', strrep(exp_name, ' + ', '_'), r);
            target_file = fullfile('results', [run_name '.mat']);
            if exist('last_run_results.mat', 'file')
                copyfile('last_run_results.mat', target_file);
                fprintf('    已保存 per-run 数据: %s\n', target_file);
            end
            
        catch ME
            fprintf('    【错误】第 %d 组 第 %d 轮失败: %s\n', i, r, ME.message);
            continue;
        end
    end
    
    % ========== 生成 summary 行（区分 Baseline） ==========
    if ~isempty(usages)
        if strcmpi(sim_mode, 'Baseline')
            % Baseline：MeanReward 和 StdReward 保持 NaN（符合“没有奖励”的实际情况）
            new_row = table({exp_name}, NaN, NaN, ...
                            mean(usages), mean(fairnesss), mean(delays), ...
                'VariableNames', {'Experiment', 'MeanReward', 'StdReward', ...
                                  'MeanUsage', 'MeanFairness', 'MeanDelay'});
        else
            new_row = table({exp_name}, mean(rewards), std(rewards), ...
                            mean(usages), mean(fairnesss), mean(delays), ...
                'VariableNames', {'Experiment', 'MeanReward', 'StdReward', ...
                                  'MeanUsage', 'MeanFairness', 'MeanDelay'});
        end
        summary = [summary; new_row];
    end
end

disp(summary);
writetable(summary, 'results/ablation_7groups.csv');
save('results/ablation_7groups.mat', 'summary');

fprintf('\n✅ 消融实验完成！per-run 数据已保存到 results/ 目录\n');
fprintf('   现在可以正常运行 plot_ablation_figures() 生成图片了。\n\n');

plot_ablation_figures();