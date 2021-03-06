classdef LogisticOutputLayer < StandardOutputLayer
   % A logistic layer with binomial cross-entropy loss function. This layer
   % ignores NaN values in the targets (useful for AutoEncoders when there
   % missing values).
   
   methods
      function obj = LogisticOutputLayer(inputSize, outputSize, varargin)
         obj = obj@StandardOutputLayer(inputSize, outputSize, varargin{:});
      end
      
      function [y, z] = feed_forward(obj, x)
         z = obj.compute_z(x);
         y = 1./(1 + exp(-z));
      end
      
      function [dLdz, y] = compute_dLdz(obj, x, t)
         [y, z] = obj.feed_forward(x);
         u = exp(-z)./(1 + exp(-z)); % u = 1 - y
         dLdz = obj.gpuState.zeros(size(y));
         idx = y<.5;
         dLdz(idx) = y(idx) - t(idx);
         dLdz(~idx) = 1 - t(~idx) - u(~idx);
         dLdz(isnan(t)) = 0;
      end

      function loss = compute_loss(~, y, t)       
         loss = nansum(-t(:).*log(y(:)) - (1 - t(:)).*log(1 - y(:)))/size(y,2);
      end
   end
   
end

