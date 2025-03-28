% Assigns quantitative values to distal nodes in the airway tree
function [B,Blabel] = airwaytreeAssociation(B,Blabel,N,voxsz,M,M_label,seg,r,func_flag)
% Inputs:
%   B           = Branches matrix
%   Blabel      = labels for columns in B
%   N           = Nodes matrix [ID,x,y,z]
%   voxsz       = voxel dimensions
%   M           = quantitative maps to associate with airway tree (4D)
%   M_label     = {1xN} labels of input image(s)
%   seg         = logical segmentation, same size as M
%   r           = radius of window
%   func_flag   = (optional) 1=mean, 2=vol%

% Find col indices for relevant values
% ID = 1 ; N_Prox = 2 ; N_Dist = 3
j_so = find(strcmp(Blabel,'Strahler'),1);
j_lobe = find(strcmp(Blabel,'Lobe'),1);
[nB,nBcol] = size(B);
nM = size(M,4);
if nargin<9
    if islogical(M)
        func_flag = 2*ones(1,nM);
    else
        func_flag = ones(1,nM);
    end
end

%% 1. Find terminal branches(sorting by soc)

edges = ( 1 : (max(B(:,j_so)))+1 ) -0.5;
soCnts = histcounts(B(:,j_so),edges);
soCnt = numel(soCnts);
B = [sortrows(B,j_so),nan(nB,1)]; % arrange with lowest SO at top


%% 3. Voxel Association (terminal airways only)

% Determine output labels
j_out = nBcol + (1:nM);
i_mean = func_flag==1;
i_pct = func_flag==2;
V_label = M_label;
V_label(i_mean) = strcat(V_label(i_mean),'_mean');
V_label(i_pct) = strcat(V_label(i_pct),'_pct');
Blabel = [Blabel,V_label]; % append to Branches table

se = calcSe(voxsz,r); % n * 3 matrix, the distance between the nodes within the range and the central nodes(end of the terminal branch).
broZ = round(N(:,2:4)./voxsz); %% Convert the coordinate into intergral
Nse = size(se,1);
for i = 1:soCnts(1)
    index = se + [broZ(B(i,3),1),broZ(B(i,3),2),broZ(B(i,3),3)]; % get the coordinate of all possible nodes (no mather if there have some values)
    num = 1; 
    tmpData = NaN(Nse,nM); % values of image(s) M within the radius r
    for j = 1:Nse
        if index(j,1) > 0 && index(j,2) >0 && index(j,3) >0 
            if index(j,1)<=size(M,1) && index(j,2)<=size(M,2) && index(j,3)<=size(M,3)  % make sure it stays in the boundary 
                % Check that voxel is in segmentation
                segflag = true;
                if ~isempty(seg)
                    segflag = logical(seg(index(j,1),index(j,2),index(j,3)));
                end
                if ~isnan(M(index(j,1),index(j,2),index(j,3))) && segflag   % whether there is data at the point
                    tmpData(num,:) = squeeze(M(index(j,1),index(j,2),index(j,3),:))';    
                    num = num+1;                
                end
            end
        end  
    end
    tmpData = tmpData(1:(num-1),:);

    % Calculate 
    if ~isnan(tmpData)
        B(i,j_out(i_mean)) = mean(tmpData(:,i_mean),1);
        B(i,j_out(i_pct)) = sum(logical(tmpData(:,i_pct)),1)/size(tmpData,1)*100;
    else
        B(i,j_out) = zeros(1,nM); %% Boxes with no voxels are signed with zero
    end
end

%% 4. Replace terminal nodes assigned to zero with mean value over all terminal nodes
indZ = B(:,j_out)==0;
indNz = B(1:soCnts(1),1)~=0;
B(indZ,:) = mean(B(indNz,:), 1) .* ones(1,nnz(indZ))';

%% 5. Calculate the value around other branches with higer so
Nso = soCnts(1);
for i = 2:soCnt  %% sort each row so as to make it easier to find mother branches
    ii = (Nso+1):(Nso+soCnts(i));
    B(ii,:) = sortrows(B(ii,:),3,'descend');
    Nso = Nso + soCnts(i);   
end

%% 7. Calc all the nodes with Strahler order larger than 1 and record the position of missing value
% (Mean of daughter nodes)
k = 0;
reChk = [1 0 0 0 0 0 0] .*ones(200,1);  %% Store the branches whose daughter branches haven't been assign with value yet.
% [postID, distID, rowIndMotherNode, rowInd_DaughterNode1, rowInd_DaughterNode2, rowInd_DaughterNode3]
    for i = (soCnts(1)+1):nB
        tmpi = find(B(:,2)==B(i,3)); %% row_th of daughter nodes
        tmpa = B(tmpi,j_out:end); %% values of daughter nodes
        %%% Finding lobe_id
        if var(B(tmpi,j_lobe)) == 0 % Lobe id of all daughter nodes are equal
            B(i,j_lobe) = B(tmpi(1),j_lobe);
        end
        %%% Assign value
        if sum(isnan(tmpa)) == 0 %~isnan(tmpa(1)) && ~isnan(tmpa(2)) which means both two daughter nodes have been found
            Nn = (tmpa ~= 0); 
            if sum(Nn(:,1)) == 0 % if daughter nodes don't have value
                B(i,j_out:end) = 0;
            else
                B(i,j_out) = mean(tmpa((Nn(:,1)~=0),1),1);
            end
        else 
            reChk(k+1,1:3) = [B(i,2:3) i]; %% [prox.id, dist.id, rows] 
            reChk(k+1,4:3+size(tmpi,1)) = tmpi'; %% dist.daughers'row (2to3 daughters),
            k = k+1;
        end
    end

%% 8. Recheck those missing data by changing sorting order of col3 each time.
reChk = reChk(1:k,:);
a = 1;
dir = {'descend','ascend'}; k = 1; % change the direction of finding nodes
%%% reChk = [prox.id, dist.id, row_id_Mother, row_id_daughter1, row_id_daughter2, row_id_daughter3, chk]
while a >0 %% whether there is NaN in reChk
    ii = find(reChk(:,6)>0); % find which nodes have three daughter branches
    for i = 1:size(reChk,1)
        if ismember(i,ii) % Indicate a node with three daughter nodes
            tmpi = reChk(i,4:6); % tmpi are the row-th for daughter nodes
        else
            tmpi = reChk(i,4:5);
        end
        if sum(isnan(B(tmpi,j_out:end))) == 0 %% if tmpi has some value
            if var(B(tmpi,j_lobe)) == 0
                B(reChk(i,3),j_lobe) = B(tmpi(1),j_lobe);
            end
            B(reChk(i,3),j_out:end) = mean(B(tmpi,j_out:end),1);
            reChk(i,7) = 1;
        end
        
    end
    a = sum(isnan(B(:,j_out:end)));
    k = mod(k,2)+1;
    reChk = sortrows(reChk,3,dir(k));     
end

%% Re-organize output values by branch ID to return
B = sortrows(B,1);






