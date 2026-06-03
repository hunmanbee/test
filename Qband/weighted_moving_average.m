function smoothed = weighted_moving_average(data, weights)
    % 加权移动平均
    n = min(length(data), length(weights));
    if n == 0
        smoothed = data(end);
    else
        valid_data = data(end-n+1:end);
        valid_weights = weights(end-n+1:end);
        smoothed = sum(valid_data .* valid_weights) / sum(valid_weights);
    end
end