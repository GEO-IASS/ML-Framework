classdef SoftabsNoParamsLayer < matlab.mixin.Copyable
   
   properties
      eps
   end
   
   methods
      function obj = SoftabsNoParamsLayer(eps)
         if nargin < 1
            eps = 1e-8;
         end
         obj.eps = eps;
      end
      
      function y = feed_forward(obj, x, isSave)
         y = sqrt(x.*x + obj.eps);
         if nargin == 3 && isSave
            obj.dydx = x./y;
         end
      end
      
      function dLdx = backprop(obj, dLdy)
         dLdx = obj.dydx.*dLdy;
         obj.dydx = [];
      end
      
   end
end
