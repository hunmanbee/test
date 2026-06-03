classdef myQueue <handle  
properties (Access = public)%private
    buffer      % a cell, to maintain the data
    beg         % the start position of the queue
    rear        % the end position of the queue
                % the actually data is buffer(beg:rear-1)
end
 
properties (Access = public)
    capacity   
end
 
methods
    function obj = myQueue(c) 
        if nargin >= 1 && iscell(c)
            obj.buffer = [c(:); cell(numel(c), 1)];% numel - Number of array elements
            obj.beg = 1;
            obj.rear = numel(c) + 1;
            obj.capacity = 2*numel(c);
        elseif nargin >= 1
            obj.buffer = cell(100, 1);
            obj.buffer{1} = c;
            obj.beg = 1;
            obj.rear = 2;
            obj.capacity = 100;                
        else
            obj.buffer = cell(100, 1);
            obj.capacity = 100;
            obj.beg = 1;
            obj.rear = 1;
        end
    end
 
    function s = size(obj) 
        if obj.rear >= obj.beg
            s = obj.rear - obj.beg;
        else
            s = obj.rear - obj.beg + obj.capacity;
        end
    end
 
    function b = isempty(obj)   % return true when the queue is empty
        b = ~logical(obj.size());
    end
 
    function s = empty(obj) % clear all the data in the queue
        s = obj.size();
        obj.beg = 1;
        obj.rear = 1;
    end
 
    function push(obj, el)
        if obj.size >= obj.capacity - 1
            sz = obj.size();
            if obj.rear >= obj.beg 
                obj.buffer(1:sz) = obj.buffer(obj.beg:obj.rear-1);                    
            else
                obj.buffer(1:sz) = obj.buffer([obj.beg:obj.capacity 1:obj.rear-1]);
            end
            obj.buffer(sz+1:obj.capacity*2) = cell(obj.capacity*2-sz, 1);
            obj.capacity = numel(obj.buffer);
            obj.beg = 1;
            obj.rear = sz+1;
        end
        obj.buffer{obj.rear} = el;
        obj.rear = mod(obj.rear, obj.capacity) + 1;
    end
 
    function el = front(obj) 
        if obj.rear ~= obj.beg
            el = obj.buffer{obj.beg};
        else
            el = [];
            warning('CQueue:NO_DATA', 'try to get data from an empty queue');
        end
    end
 
    function el = back(obj)         
 
       if obj.rear == obj.beg
           el = [];
           warning('CQueue:NO_DATA', 'try to get data from an empty queue');
       else
           if obj.rear == 1
               el = obj.buffer{obj.capacity};
           else
               el = obj.buffer{obj.rear - 1};
           end
        end
 
    end
 
    function el = pop(obj) 
        if obj.rear == obj.beg
            error('CQueue:NO_Data', 'Trying to pop an empty queue');
        else
            el = obj.buffer{obj.beg};
            obj.beg = obj.beg + 1;
            if obj.beg > obj.capacity, obj.beg = 1; end
        end             
    end
 
    function remove(obj) 
        obj.beg = 1;
        obj.rear = 1;
    end
 
    function display(obj)
        if obj.size()
            if obj.beg <= obj.rear 
                for i = obj.beg : obj.rear-1
                    disp([num2str(i - obj.beg + 1) '-th element of the stack:']);
                    disp(obj.buffer{i});
                end
            else
                for i = obj.beg : obj.capacity
                    disp([num2str(i - obj.beg + 1) '-th element of the stack:']);
                    disp(obj.buffer{i});
                end     
                for i = 1 : obj.rear-1
                    disp([num2str(i + obj.capacity - obj.beg + 1) '-th element of the stack:']);
                    disp(obj.buffer{i});
                end
            end
        else
            disp('The queue is empty');
        end
    end
 
    function c = content(obj) 
        if obj.rear >= obj.beg
            c = obj.buffer(obj.beg:obj.rear-1);                    
        else
            c = obj.buffer([obj.beg:obj.capacity 1:obj.rear-1]);
        end
    end
    function length = getLength(obj) 
        length = obj.size();
    end   
end
end