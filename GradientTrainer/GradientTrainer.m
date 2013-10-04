classdef GradientTrainer < handle
   % Manages supervised learning of Models that respond to 'gradient(x, t)' method.
   %
   % Key properties that should be set manually before trian() is called:
   %
   % dataManager - stores training and validation data, serves batches, and
   % notifies when an epoch has completed.
   %
   % model - a supervised learning model that responds to 'gradient(x,t)'
   % to compute the gradient for inputs x and targets t.
   % 
   % reporter (optional) - displays information regarding training
   % progress.
   %
   % stepCalculator - uses gradients generated by model to determine a step
   % direction and size for each batch. Receives parameter updates from
   % trainingSchedule as training progresses.
   %
   % trainingSchedule - determines when training should terminate and
   % updates parameters of stepCalculator as learning progresses.
   %
   % The copy() method yields a deep copy of the GradientTrainer object.
   %
   % The reset() method calls the reset() method on each of the
   % GradientTrainer properties.
   
   properties
      dataManager % an object that implements the DataManager interface
      model % an object that implements the Model interface
      reporter % an object that implements the Reporter interface
      stepCalculator % an object that implements the StepCalculator interface
      trainingSchedule % an object that implements the TrainingSchedule interface
   end
   
   methods
      function train(obj)
         % Trains the model object by incrementing the model parameters by
         % steps determined by the stepCalculator object. Training is terminated 
         % when trainingSchedule indicates to stop.
         
         isContinue = true;
         while isContinue
            [x, t, isEndOfEpoch] = obj.dataManager.next_batch();
            obj.stepCalculator.take_step(x, t, obj.model, obj.trainingSchedule.params);
            
            if isEndOfEpoch
               trainingLoss = ...
                  obj.model.compute_loss(obj.model.output(obj.dataManager.trainingInputs), ...
                                         obj.dataManager.trainingTargets);
               validationLoss = ...
                  obj.model.compute_loss(obj.model.output(obj.dataManager.validationInputs), ...
                                         obj.dataManager.validationTargets);
                                                    
               if ~isempty(obj.reporter)
                  obj.reporter.update(trainingLoss, validationLoss);
               end
               isContinue = obj.trainingSchedule.update(obj, trainingLoss, validationLoss);
            end             
         end
      end
      
      function objCopy = copy(obj)
         % Yields a deep copy of the GraidentTrainer object.
         objCopy = GradientTrainer();
         objCopy.dataManager = copy(obj.dataManager);
         objCopy.model = copy(obj.model);
         if ~isempty(obj.reporter)
            objCopy.reporter = copy(obj.reporter);
         end
         objCopy.stepCalculator = copy(obj.stepCalculator);
         objCopy.trainingSchedule = copy(obj.trainingSchedule);
      end
      
      function reset(obj)
         % Calls reset() on all properties of the GradientTrainer object.
         if ~isempty(obj.reporter)
            obj.reporter.reset();
         end
         
         if ~isempty(obj.stepCalculator)
            obj.stepCalculator.reset();
         end
         
         if ~isempty(obj.trainingSchedule)
            obj.trainingSchedule.reset();
         end
         
         if ~isempty(obj.dataManager)
            obj.dataManager.reset();
         end
         
         if ~isempty(obj.model)
            obj.model.reset();
         end
      end
   end      
end

