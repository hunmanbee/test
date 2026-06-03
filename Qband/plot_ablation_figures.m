function plot_ablation_figures()
% 最终改进版：对比式绘图 + 更好容错（推荐论文使用）

    if ~exist('results/figures', 'dir')
        mkdir('results/figures');
    end

    load('results/ablation_7groups.mat');
    fprintf('开始生成消融实验图片（改进版）...\n');

    cmap = lines(7);

    %% ==================== Fig1: 主结果柱状图（已优化误差棒） ====================
    figure('Position', [100 100 1600 550]);
    subplot(1,4,1);
    bar(summary.MeanReward, 'FaceColor', cmap(1,:)); hold on;
    errorbar(1:height(summary), summary.MeanReward, summary.StdReward, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 10);
    ylabel('Average Reward', 'FontSize', 11); title('(a) Average Reward', 'FontSize', 12, 'FontWeight', 'bold'); grid on;

    subplot(1,4,2);
    bar(summary.MeanFairness, 'FaceColor', cmap(2,:)); hold on;
    errorbar(1:height(summary), summary.MeanFairness, summary.StdReward*0.05, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 10);
    ylabel('Jain''s Fairness Index', 'FontSize', 11); title('(b) Fairness Index', 'FontSize', 12, 'FontWeight', 'bold'); grid on;

    subplot(1,4,3);
    bar(summary.MeanUsage, 'FaceColor', cmap(3,:)); hold on;
    errorbar(1:height(summary), summary.MeanUsage, summary.StdReward*0.03, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 10);
    ylabel('Average Usage Rate', 'FontSize', 11); title('(c) Channel Usage', 'FontSize', 12, 'FontWeight', 'bold'); grid on;

    subplot(1,4,4);
    bar(summary.MeanDelay, 'FaceColor', cmap(4,:)); hold on;
    errorbar(1:height(summary), summary.MeanDelay, summary.StdReward*0.2, 'k.', 'LineWidth', 1.5, 'CapSize', 6);
    set(gca, 'XTickLabel', summary.Experiment, 'XTickLabelRotation', 35, 'FontSize', 10);
    ylabel('Average Delay (ms)', 'FontSize', 11); title('(d) Average Delay', 'FontSize', 12, 'FontWeight', 'bold'); grid on;

    sgtitle('Ablation Study Results (7 Methods)', 'FontSize', 14, 'FontWeight', 'bold');
    saveas(gcf, 'results/figures/Fig1_Ablation_Results.png');
    fprintf('Fig1 已保存\n');

    %% ==================== Fig2: Training Curves（只画RL相关组） ====================
    figure('Position', [100 100 900 550]); hold on;
    rl_groups = {'RL_full', 'RL_no_fairness', 'RL_no_diversity', 'DQN'};
    for i = 1:length(rl_groups)
        filename = sprintf('results/%s_run1.mat', rl_groups{i});
        if exist(filename, 'file')
            try
                load(filename);
                if ~isempty(reward_history) && length(reward_history) > 5
                    plot(reward_history, 'Color', cmap(i,:), 'LineWidth', 1.8, 'DisplayName', rl_groups{i});
                end
            catch
            end
        end
    end
    xlabel('Decision Steps (every 10ms)', 'FontSize', 11);
    ylabel('Average Reward', 'FontSize', 11);
    title('Training Curves Comparison (RL Methods)', 'FontSize', 13, 'FontWeight', 'bold');
    legend('Location', 'southeast', 'FontSize', 10); grid on;
    saveas(gcf, 'results/figures/Fig2_Training_Curves.png');
    fprintf('Fig2 已保存\n');

    %% ==================== Fig3: Delay CDF（改进版，尝试画更多组） ====================
    figure('Position', [100 100 900 550]); hold on;
    cdf_groups = {'RL_full', 'RL_no_fairness', 'DQN', 'Baseline_greedy', 'Baseline_fixed'};
    for i = 1:length(cdf_groups)
        filename = sprintf('results/%s_run1.mat', cdf_groups{i});
        if exist(filename, 'file')
            try
                load(filename);
                if ~isempty(delay_history) && length(delay_history) > 10
                    [f, x] = ecdf(delay_history);
                    plot(x, f, 'Color', cmap(i,:), 'LineWidth', 2.0, 'DisplayName', cdf_groups{i});
                end
            catch
            end
        end
    end
    xlabel('Delay (ms)', 'FontSize', 11);
    ylabel('CDF', 'FontSize', 11);
    title('CDF of Packet Delay (Multiple Methods)', 'FontSize', 13, 'FontWeight', 'bold');
    legend('Location', 'southeast', 'FontSize', 9); grid on;
    saveas(gcf, 'results/figures/Fig3_Delay_CDF.png');
    fprintf('Fig3 已保存（已尝试包含更多组）\n');

    %% ==================== Fig4: Reward Boxplot ====================
    figure('Position', [100 100 950 550]);
    all_rewards = []; labels = [];
    for i = 1:height(summary)
        mode = summary.Experiment{i};
        for r = 1:3   % 用3轮做boxplot
            filename = sprintf('results/%s_run%d.mat', mode, r);
            if exist(filename, 'file')
                try
                    load(filename);
                    if ~isempty(reward_history)
                        all_rewards = [all_rewards; mean(reward_history)];
                        labels = [labels; {mode}];
                    end
                catch
                end
            end
        end
    end
    if ~isempty(all_rewards)
        boxplot(all_rewards, labels);
        ylabel('Average Reward', 'FontSize', 11);
        title('Reward Distribution Across Runs', 'FontSize', 13, 'FontWeight', 'bold');
        grid on; set(gca, 'FontSize', 10, 'XTickLabelRotation', 30);
    end
    saveas(gcf, 'results/figures/Fig4_Reward_Boxplot.png');
    fprintf('Fig4 已保存\n');

    fprintf('\n✅ 所有图片已更新并保存到 results/figures/\n');
end