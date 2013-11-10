clear all
load reduced_MNIST

targets(targets == 0) = -1;
testTargets(testTargets == 0) = -1;

ffn = FeedForwardNet('inputDropout', .2, 'hiddenDropout', .5);
ffn.hiddenLayers = {MaxoutHiddenLayer(717, 768, 5, 'initScale', .005)};
ffn.outputLayer = SVMOutputLayer(768, 10, 'L2Penalty', 1e-5, 'initScale', 0);

sampler = ProportionSubsampler(5/6);
[trainIdx, validIdx] = sampler.sample(1:60000);
trainInputs = inputs(:,trainIdx);
trainTargets = targets(:, trainIdx);
validInputs = inputs(:,validIdx);
validTargets = targets(:,validIdx);
clear inputs targets

trainer = GradientTrainer();
trainer.dataManager = DataManager({trainInputs, trainTargets}, {validInputs, validTargets}, ...
                                    'batchSize', 256);
trainer.reporter = ConsoleReporter();
trainer.stepCalculator = NesterovMomentum();
trainer.model = ffn;
trainer.trainingSchedule = MomentumSchedule(100, .01, .99, 'lrDecay', .995, 'C', 1);
trainer.train();

%% Evaluate on test set
[~, predictions] = max(ffn.output(testInputs));
[~, actual] = max(testTargets);
nErrors = sum(predictions~=actual)