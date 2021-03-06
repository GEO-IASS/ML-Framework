classdef FeedForwardNet < Model
   % A feed-forward neural network that can utilize dropout and gpu training. 

   properties
      hiddenLayers % cell array of HiddenLayer objects (possibly empty)
      outputLayer % a single OutputLayer object
      gpuState % gpuState object used for array creation
      
      % proportion of inputs that are replaced with 0
      inputDropout 
      
      % An array of dropout probabilities for the hiddenLayers; should have same
      % length as hiddenLayers or be a single scalar (in which case the same 
      % value is used for all hiddenLayers); values are probability that 
      % hidden unit activation is replaced by 0
      hiddenDropout 
      
      % a row vector of integer values describing the nested gradient shape;
      % this value is computed on the first backprop pass
      nestedGradShape 
      
      % the length of the flattened gradient; computed on the first 
      % backprop pass
      flatGradLength 
   end
   
   methods
      function obj = FeedForwardNet(varargin)
         p = inputParser;
         p.addParamValue('hiddenDropout', 0);
         p.addParamValue('inputDropout', 0);
         p.addParamValue('gpu', []);         
         parse(p, varargin{:});
         
         obj.hiddenDropout = p.Results.hiddenDropout;
         obj.inputDropout = p.Results.inputDropout;
         obj.gpuState = GPUState(p.Results.gpu);
      end
      
      
      function gather(obj)
         for i = 1:length(obj.hiddenLayers);
            obj.hiddenLayers{i}.gather();
         end
         obj.outputLayer.gather();
         obj.gpuState.isGPU = false;
      end
      
      
      function push_to_GPU(obj)
         for i = 1:length(obj.hiddenLayers)
            obj.hiddenLayers{i}.push_to_GPU();
         end
         obj.outputLayer.push_to_GPU();
         obj.gpuState.isGPU = true;
      end      
      
      
      function increment_params(obj, delta_params)         
         if isempty(obj.hiddenLayers)
            obj.outputLayer.increment_params(delta_params);
         else
            % delta_params is a flat cell array; it must be rolled into proper
            % nested shape (as originally produced during the layer by layer 
            % gradient computation) before updating each layer params.
            
            delta_params = obj.roll_gradient(delta_params);
            
            for i = 1:length(obj.hiddenLayers)
               obj.hiddenLayers{i}.increment_params(delta_params{i});
            end
            obj.outputLayer.increment_params(delta_params{end});
         end
      end
      
      
      function [grad, output, dLdx] = gradient(obj, batch, isSample)
         % batch = {x, t} where x is input and t is target. Computes the 
         % gradient for mean loss on batch with respect to parameters in each 
         % hiddenLayer and outputLayer. isSample is a boolean flag where true
         % means that hidden units will randomly be dropped out, and false means
         % all hidden units are kept but rescaled by (1 - dropoutProb).
         
         if nargin < 3
            isSample = true;
         end
         
         x = batch{1};
         t = batch{2};
 
         % feed_forward through hiddenLayers
         [y, mask] = obj.feed_forward(x, isSample);
         
         % get outputLayer output and backpropagate loss
         [grad, output, dLdx] = obj.backprop(y, t, mask);
      end
      
      
      function [y, mask] = feed_forward(obj, x, isSample)
         % Expand obj.hiddenDropout if it is a scalar       
         if isscalar(obj.hiddenDropout)
            obj.hiddenDropout = ...
               obj.hiddenDropout*ones(1, length(obj.hiddenLayers));
         end

         nHiddenLayers = length(obj.hiddenLayers);
         
         % output from each hiddenLayer (and y{1} = input)
         y = cell(1, nHiddenLayers+1); 
         
         % dropout mask for each layer (including input)
         mask = cell(1, nHiddenLayers+1); 
         
         if obj.inputDropout > 0
            if isSample
               mask{1} = obj.compute_dropout_mask(size(x), 1);
               y{1} = x.*mask{1};
            else
               y{1} = (1 - obj.inputDropout)*x;
            end
         else
            y{1} = x;
         end

         % Feed-forward through hidden layers
         for i = 1:nHiddenLayers
            y{i+1} = obj.hiddenLayers{i}.feed_forward(y{i}, true);
            if obj.hiddenDropout(i) > 0
               if isSample
                  mask{i+1} = obj.compute_dropout_mask(size(y{i+1}), i+1);
                  y{i+1} = y{i+1}.*mask{i+1};
               else
                  y{i+1} = (1-obj.hiddenDropout(i))*y{i+1};
               end
            end
         end
      end
      
      
      function [grad, output, dLdx] = backprop(obj, y, t, mask)
         nHiddenLayers = length(obj.hiddenLayers);
         grad = cell(1, nHiddenLayers+1); % gradient of hiddenLayers and 
                                          % outputLayer (nested shape)
                                          
         [grad{end}, dLdx, output] = obj.outputLayer.backprop(y{end}, t);
         if ~isempty(mask{end})
            dLdx = dLdx.*mask{end};
         end
         
         for i = nHiddenLayers:-1:1
            [grad{i}, dLdx] = obj.hiddenLayers{i}.backprop(y{i}, y{i+1}, dLdx);
            if ~isempty(mask{i})
               dLdx = dLdx.*mask{i};
            end
         end
         
         grad = obj.unroll_gradient(grad);
      end
      
      
      function mask = compute_dropout_mask(obj, sizeVec, idx)   
         % Computes a binary (0, 1) mask  of specified size for a specific
         % layer index (idx = 1 is input layer)

         if idx == 1 % Input layer
            mask = obj.gpuState.binary_mask(sizeVec, obj.inputDropout);
         else % hiddenLayers{idx-1}
            mask = obj.gpuState.binary_mask(sizeVec, obj.hiddenDropout(idx-1));
         end
      end
      
      
      function y = output(obj, x)
         if obj.inputDropout > 0
            y = (1-obj.inputDropout)*x;
         else
            y = x;
         end
         
         for i = 1:length(obj.hiddenLayers)
            y = obj.hiddenLayers{i}.feed_forward(y);
            if obj.hiddenDropout(i) > 0
               y = (1-obj.hiddenDropout(i))*y;
            end
         end
         y = obj.outputLayer.feed_forward(y);
      end
      
      
      function loss = compute_loss(obj, batch)
         y = obj.output(batch{1});
         t = batch{2};
         loss = obj.compute_loss_from_output(y, t);
      end
      
      
      function loss = compute_loss_from_output(obj, y, t)
         loss = obj.outputLayer.compute_loss(y, t);
      end
      
      
      function objCopy = copy(obj)
         objCopy = FeedForwardNet();
         
         % Handle class properties
         objCopy.hiddenLayers = cell(size(obj.hiddenLayers));
         for idx = 1:length(obj.hiddenLayers)
            objCopy.hiddenLayers{idx} = copy(obj.hiddenLayers{idx});
         end
         
         if ~isempty(obj.outputLayer)
            objCopy.outputLayer = copy(obj.outputLayer);
         end
         
         % Value class properties
         objCopy.gpuState = obj.gpuState;
         objCopy.inputDropout = obj.inputDropout;
         objCopy.hiddenDropout = obj.hiddenDropout;
         objCopy.nestedGradShape = obj.nestedGradShape;
         objCopy.flatGradLength = obj.flatGradLength;
      end
      
      
      function reset(obj)
         for i = 1:length(obj.hiddenLayers)
            obj.hiddenLayers{i}.init_params();
         end
         obj.outputLayer.init_params();
         obj.nestedGradShape = [];
         obj.flatGradLength = [];
      end
      
      
      function flatGrad = unroll_gradient(obj, nestedGrad)
         if isempty(obj.nestedGradShape)
            obj.compute_gradient_shapes(nestedGrad);
         end
         
         flatGrad = cell(1, obj.flatGradLength);
         startIdx = 1;
         for i = 1:length(nestedGrad)
            stopIdx = startIdx + obj.nestedGradShape(i) - 1;
            flatGrad(startIdx:stopIdx) = nestedGrad{i};
            startIdx = stopIdx + 1;
         end
      end
      
      
      function nestedGrad = roll_gradient(obj, flatGrad)
         startIdx = 1;
         nestedLength = length(obj.nestedGradShape);
         nestedGrad = cell(1, nestedLength);
         for i = 1:nestedLength
            stopIdx = startIdx + obj.nestedGradShape(i) - 1;
            nestedGrad{i} = flatGrad(startIdx:stopIdx);
            startIdx = stopIdx + 1;
         end
      end
      
      
      function compute_gradient_shapes(obj, nestedGrad)
         flatLength = 0;
         nestedShape = zeros(1, length(nestedGrad));
         for i = 1:length(nestedGrad)
            nestedShape(i) = length(nestedGrad{i});
            flatLength = flatLength + nestedShape(i);
         end
         obj.nestedGradShape = nestedShape;
         obj.flatGradLength = flatLength;
      end
      
   end
end

