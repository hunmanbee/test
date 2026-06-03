function [structA] = structAssign(structA, structB)
% 将 structB 中与 structA 相同字段的成员的值赋值给 structA 对应的成员

    keys = fieldnames(structB); % 获得结构体B的所有字段
    for i = 1:length(keys)
        cur_key = keys{i};
        if isfield(structA, cur_key)
            % 2017年后支持: structName.(dynamicExpression)
            % dynamicExpression 是一个变量或表达式，返回字符串标量（结构体字段）
            % 类似于 getfield() 和 setfield() 功能
            structA.(cur_key) = structB.(cur_key);
        else
            warming('字段"%s"不存在!', cur_key);
        end
    end

end