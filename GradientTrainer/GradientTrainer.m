classdef GradientTrainer < handle
   % Manages supervised learning of Models that respond to 'gradient(x, t)' method.
   %
   % Key properties that should be set manually before trian() is called:
   %
   % dataManager - stores training and validation data, and serves batches
   %
   % model - a model that responds to 'gradient(batch)'
   %
   % stepCalculator - uses gradients generated by model to determine a step
   % direction and size for each batch. Receives parameter updates from
   % parameterSchedule as training progresses.
   %
   % parameterSchedule - updates parameters of stepCalculator as learning progresses.
   %
   % progressMonitor - computes any relevant progress data (on training
   % and/or validation set) and determines when training should terminate
   %
   % The reset() method calls the reset() method on each of the
   % GradientTrainer properties.
   
   properties
      dataManager % an object that implements the DataManager interface
      model % an object that implements the Model interface
      progressMonitor % computes performance metrics and can send stop signal to terminate training
      parameterSchedule % computes the training parameters used in stepCalculator
      stepCalculator % an object that implements the StepCalculator interface
   end
   
   methods
      function train(obj, maxUpdates)         
         isContinue = true;
         nUpdates = 0;
         while isContinue
            nUpdates = nUpdates + 1;
            batch = obj.dataManager.next_batch();
            if isempty(obj.parameterSchedule)
               params = [];
            else
               params = obj.parameterSchedule.update();
            end
            obj.stepCalculator.take_step(batch, obj.model, params);
            if ~isempty(obj.progressMonitor)
               isContinue = obj.progressMonitor.update(obj.model, obj.dataManager); 
            end
            if nUpdates >= maxUpdates
               break;
            end
         end
      end
      
      function reset(obj)
         % Calls reset() on all properties of the GradientTrainer object that are not empty
         if ~isempty(obj.dataManager)
            obj.dataManager.reset();
         end
         
         if ~isempty(obj.model)
            obj.model.reset();
         end
         
         if ~isempty(obj.progressMonitor)
            obj.progressMonitor.reset();
         end
         
         if ~isempty(obj.parameterSchedule)
            obj.parameterSchedule.reset();
         end
         
         if ~isempty(obj.stepCalculator)
            obj.stepCalculator.reset();
         end
      end
   end      
end

