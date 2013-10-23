classdef HiddenLayer < matlab.mixin.Copyable
   % Defines the HiddenLayer interface 

   methods (Abstract)
      [grad, dLdx, dydz] = backprop(obj, x, y, dLdy)
      y = feed_forward(obj, x)
      value = compute_z(obj, x)
      value = compute_dydz(obj, x, y)
      push_to_GPU(obj)
      gather(obj)
      increment_params(obj, delta_params)
      init_params(obj)
   end
   
end

