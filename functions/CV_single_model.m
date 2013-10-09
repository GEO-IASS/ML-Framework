function [outputs, testLoss, models, hold_outs] = ...
            CV_single_model(inputs, targets, nFolds, train_model_function, varargin)

         
         
if isempty(targets) % no targets => AutoEncoder training - use inputs as targets
   targets = inputs;
end

[outputSize, dataSize] = size(targets);
models = cell(1, nFolds);
gpuState = GPUState();
outputs = gpuState.zeros(outputSize, dataSize);

hold_outs = CV_partition(dataSize, nFolds);

for i = 1:nFolds
   testSplit = hold_outs{i};
   trainSplit = setdiff(1:dataSize, testSplit);
   models{i} = train_model_function(inputs(:,trainSplit), targets(:,trainSplit), varargin);
   outputs(:, testSplit) = models{i}.output(inputs(:, testSplit));
end

testLoss = models{1}.compute_loss(outputs, targets);

end

