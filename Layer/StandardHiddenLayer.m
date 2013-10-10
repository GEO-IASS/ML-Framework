classdef StandardHiddenLayer < HiddenLayer & StandardLayer
   
   methods
      function obj = StandardHiddenLayer(inputSize, outputSize, varargin)
         obj = obj@StandardLayer(inputSize, outputSize, varargin{:});
      end
      
      function [grad, dLdx] = backprop(obj, x, y, dLdy)
         dLdz = dLdy.*obj.dydz(y);
         dLdx = obj.params{1}'*dLdz;
         grad = obj.grad_from_dLdz(x, dLdz);
      end
   end
   
   methods (Abstract)
      value = dydz(~, y)
   end
   
end

