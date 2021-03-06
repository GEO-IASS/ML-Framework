classdef Conv2DDivisiveNormalization < CompositeHigherLayer & ...
                                       matlab.mixin.Copyable
   % Performs divisive contrast normalization over Gaussian
   % window and accross feature maps (see LeCun2010 "Convolutional networks
   % and applications in vision")
   
   properties
      windowSize % (wS) The Gaussian weighting window is a wS x wS square
      W % weight coefficients for Gaussian weighting window (1 x 1 x wS x wS)
      gpuState
      
      % A 1 x 1 x rows x cols matrix the same size as a single input channel 
      % with edge correction coeffs that make gaussian filter keep sum of 1
      edgeFactor 
      
      x % C x N x rows x cols
      sigma % 1 x N x rows x cols
      meanSigma % 1 x N
   end
   
   methods
      function obj = Conv2DDivisiveNormalization(windowSize, channels, gpu)
         obj.windowSize = windowSize;
         if nargin < 3
            obj.gpuState = GPUState();
         else
            obj.gpuState = GPUState(gpu);
         end
         obj.W = obj.compute_weights(channels);
      end
      
      function y = feed_forward(obj, x, isSave)
         radius = (obj.windowSize-1)/2;
         [C, N, rows, cols] = size(x);
         sigma = obj.gpuState.nan(1,N,rows,cols); %#ok<*PROP>
         
         if isempty(obj.edgeFactor)
            isStoreEdgeFactor = true;
            obj.edgeFactor = obj.gpuState.ones(1, 1, rows, cols);
         else
            isStoreEdgeFactor = false;
         end
         
         for i = 1:rows
            for j = 1:cols
               % Test for edge effects; may need to truncate filter window               
               if i < radius+1 || i > rows-radius || ... 
                     j < radius+1 || j > cols-radius     
                  samp = x(:,:,max(1,i-radius):min(rows,i+radius), ...
                               max(1,j-radius):min(cols,j+radius));
                  topRoom = min(radius, i-1);
                  bottomRoom = min(radius, rows-i);
                  leftRoom = min(radius, j-1);
                  rightRoom = min(radius, cols-j);
                  center = radius+1;
                  truncW = obj.W(1, 1, center-topRoom:center+bottomRoom, ...
                                       center-leftRoom:center+rightRoom);
                  if isStoreEdgeFactor
                     obj.edgeFactor(:,:,i,j) = C*sum(truncW(:));
                  end
                  sigma(:,:,i,j) = sqrt(sum(sum(sum(bsxfun(@times, ...
                     truncW/obj.edgeFactor(:,:,i,j), samp.*samp), 4), 3), 1));
               else   % Interior, can use full filter
                  samp = x(:,:,i-radius:i+radius, j-radius:j+radius);
                  sigma(:,:,i,j) = sqrt(sum(sum(sum(bsxfun(@times, obj.W, ...
                                                    samp.*samp), 4), 3), 1));
               end
            end
         end
         meanSigma = mean(mean(sigma, 4), 3); % 1 x N
         y = bsxfun(@rdivide, x, bsxfun(@max, sigma, meanSigma));
         
         if nargin == 3 && isSave
            obj.x = x;
            obj.sigma = sigma;
            obj.meanSigma = meanSigma;
         end
      end
      
      function dLdx = backprop(obj, dLdy)
         radius = (obj.windowSize-1)/2;
         [~, N, rows, cols] = size(dLdy);
         convTerm1 = obj.gpuState.nan(1, N, rows, cols);
         convTerm2 = obj.gpuState.nan(1, N, rows, cols);
         sigmaLarge = bsxfun(@gt, obj.sigma, obj.meanSigma);
         sigmaSmall = bsxfun(@le, obj.sigma, obj.meanSigma);
         
         for i = 1:rows
            for j = 1:cols
               % Test for edge effects; may need to truncate filter window   
               if i < radius+1 || i > rows-radius || ...
                     j < radius+1 || j > cols-radius     
                  rS = max(1, i-radius); % rowStart
                  rE = min(rows, i+radius); % rowEnd
                  cS = max(1, j-radius); % colStart
                  cE = min(cols, j+radius); % colEnd
                  samp1 = sum(dLdy(:,:,rS:rE,cS:cE).*...
                         obj.x(:,:,rS:rE,cS:cE), 1).*...
                         sigmaLarge(:,:,rS:rE,cS:cE)./...
                         bsxfun(@times, obj.edgeFactor(:,:,rS:rE,cS:cE), ...
                                        obj.sigma(:,:,rS:rE,cS:cE).^3);
                  samp1(isnan(samp1)) = 0; % in case sigma == 0 somewhere
                  
                  topRoom = min(radius, i-1);
                  bottomRoom = min(radius, rows-i);
                  leftRoom = min(radius, j-1);
                  rightRoom = min(radius, cols-j);
                  center = radius+1;
                  truncW = obj.W(1,1,center-topRoom:center+bottomRoom, ...
                                     center-leftRoom:center+rightRoom);
                  convTerm1(:,:,i,j) = sum(sum(bsxfun(@times, truncW, samp1),...
                                                                      4), 3);
                  
                  % Possibly optimize by not computing when 
                  % all(x(:,:,i,j), 1) == 0
                  samp2 = bsxfun(@times, obj.edgeFactor(:,:,rS:rE,cS:cE), ...
                                         obj.sigma(:,:,rS:rE,cS:cE));
                  convTerm2(:,:,i,j) = sum(sum(bsxfun(@rdivide, truncW, ...
                                                      samp2), 4), 3);
               else   % Interior, can use full filter 
                      % (still need to account for edgeFactors)
                  rS = i-radius;
                  rE = i+radius;
                  cS = j-radius;
                  cE = j+radius;
                  samp1 = sum(dLdy(:,:,rS:rE,cS:cE).*...
                             obj.x(:,:,rS:rE,cS:cE), 1).*...
                             sigmaLarge(:,:,rS:rE,cS:cE)./...
                             bsxfun(@times, obj.edgeFactor(:,:,rS:rE,cS:cE), ...
                                            obj.sigma(:,:,rS:rE,cS:cE).^3);
                  samp1(isnan(samp1)) = 0; % in case sigma == 0 somewhere
                  convTerm1(:,:,i,j) = sum(sum(bsxfun(@times, obj.W, samp1), ...
                                                      4), 3);
                  
                  samp2 = bsxfun(@times, obj.edgeFactor(:,:,rS:rE,cS:cE), ...
                                         obj.sigma(:,:,rS:rE,cS:cE));
                  convTerm2(:,:,i,j) = sum(sum(bsxfun(@rdivide, obj.W, ...
                                                      samp2), 4), 3);
               end
            end
         end
         % fix cases where sigma == 0 (corresponds to x == 0)
         convTerm2(isinf(convTerm2)) = 0; 
         temp1 = sum(sum(sigmaSmall.*sum(dLdy.*obj.x, 1), 4), 3)./...
                                         obj.meanSigma.^2; % 1 x N
         dLdx = bsxfun(@rdivide, dLdy, ...
                       bsxfun(@max, obj.sigma, obj.meanSigma)) - ...
                       bsxfun(@times, obj.x, convTerm1) - ...
                       bsxfun(@times, temp1, bsxfun(@times, obj.x/...
                                                     (rows*cols), convTerm2));
         obj.x = [];
         obj.sigma = [];
         obj.meanSigma = [];
      end
      
      function W = compute_weights(obj, channels)
         % Assumes windowSize is odd
         x = obj.gpuState.linspace(-2, 2, obj.windowSize);
         W = exp(-bsxfun(@plus, x.*x, x'.*x')/2)/(2*pi);
         W = shiftdim(W/(channels*sum(W(:))), -2);
      end
      
   end
end

