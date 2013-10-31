classdef TanhHiddenLayer < StandardHiddenLayer
   
   properties
      isLocallyLinear = false
      isDiagonalDy = true
   end
   
   methods
      function obj = TanhHiddenLayer(inputSize, outputSize, varargin)
         obj = obj@StandardHiddenLayer(inputSize, outputSize, varargin{:});
      end
      
      function y = feed_forward(obj, x)
         z = obj.compute_z(x);
         y = tanh(z);
      end
      
      function value = compute_Dy(~, ~, y)
         value = (1 + y).*(1 - y);
      end
      
      function value = compute_D2y(~, ~, y, Dy)
         value = -2*y.*Dy;
      end
   end
   
end

