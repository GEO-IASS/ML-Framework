function [xNorm, transforms, xL, xU] = normalize_transform(x, isClipping)
% Uses a GLM with predictors [1, x, log(x)] and probit link function to fit
% the empirical cdf of data. Data is then transformed according to the fit
% GLM parameters so that normed_data is roughly normal. This is equivalent
% to translating, rescaling and combining with the log transformed data in
% an effort to normalize (based on fitting normal cdf).
%
% If isClipping is true, the top and bottom 1% are clipped to 1% or 99%
% before transforming (and xL and xU are returned for later
% transformations).

if nargin < 2
   isClipping = false;
end

gpuState = GPUState(isa(x, 'gpuArray'));

% Compute the transforms
[M, N] = size(x);
q = (tiedrank(x') - .5)/N; % N x M
y = norminv(q, 0, 1); % N x M
%minVal = exp(min(y)); % 1 x M
%x = bsxfun(@minus, x, min(x, [], 2) - minVal'); % shift x so that minvalue corresponds to expected min if lognormal(0,1)

xClipped = x;
xClipped(q' < .01) = NaN;
xClipped(q' > .99) = NaN;

transforms = zeros(3, M);
for i = 1:M
   R(:, 1) = xClipped(i,:)';
   R(:, 2) = log(xClipped(i,:))';
   transforms(:,i) = robustfit(R, y(:,i));
end

% Apply transforms to data
transforms = transforms';

xL = [];
xU = [];
if isClipping
   xL = nanmin(xClipped, [], 2);
   xU = nanmax(xClipped, [], 2);
   x = bsxfun(@min, xU, bsxfun(@max, x, xL));
end
xNorm = bsxfun(@times, transforms(:,1), gpuState.ones([M,N])) + ...
         bsxfun(@times, transforms(:,2), x) + ...
         bsxfun(@times, transforms(:,3), log(x));
end

