function [img,label,fov,orient,info] = readDICOM(varargin)

noprompt = false;
din = [];
fname = '';
gap_str = 'Concatenate';

for i = 1:numel(varargin)
    if ischar(varargin{i})
        if strcmp(varargin{i},'noprompt')
            noprompt = true;
        elseif strcmp(varargin{i},'Insert Gaps')
            gap_str = 'Insert Gaps';
            noprompt = true;
        elseif isfolder(varargin{i}) || exist(varargin{i},'file')
            fname = varargin{i};
        end
    elseif isnumeric(varargin{i}) && numel(varargin{i})==3
        din = varargin{i};
    end
end

img = []; label = {}; fov = [];

% Assumes DICOMS are stored by case in a folder
if isfolder(fname)
    fpath = fname;
elseif exist(fname,'file')==2
    fpath = fileparts(fname);
else
    error('Invalid input for readDICOM: %s',fname);
end

% Check for dicomdir file:
fname = dir(fpath);
fname([fname.isdir]) = [];
fname = {fname(:).name};
fname(ismember(fname,{'.','..'})) = [];
ind = find(strcmpi('dicomdir',fname),1);
if ind
    % DICOM names are stored in "DICOMDIR" file
    %     hp = waitbar(0,'Reading DICOMDIR ...');
    fprintf('\nReading DICOMDIR ...\n');
    tinfo = dicominfo(fullfile(fpath,fname{ind}),'UseDictionaryVR',true);
    fname = fieldnames(tinfo.DirectoryRecordSequence);
    nf = length(fname);
    ind = false(1,nf);
    fprintf('Finding file locations ');
    for i = 1:nf
        if isfield(tinfo.DirectoryRecordSequence.(fname{i}),'ReferencedFileID')
            tdir = tinfo.DirectoryRecordSequence.(fname{i}).ReferencedFileID;
            fname{i} = strrep(tdir,'\',filesep);
        else
            ind(i) = true;
        end
        %         waitbar(i/nf,hp,'Finding file locations ...');
        if ~mod(i,round(nf/20))
            fprintf('.');
        end
    end
    %     delete(hp);
    fprintf('\n');
    fname(ind) = [];
    nf = nf - nnz(ind);
else
    % All DICOMs are in single directory
    fname(~cellfun(@isdicom,fullfile(fpath,fname))) = [];
    nf = length(fname);
end

dcmdata = struct('SeriesInstanceUID',{},... % for sorting multiple images
    'img',{},...
    'd',{},...
    'AcquisitionNumber',{},...
    'SeriesNumber',{},...
    'TemporalPositionIdentifier',{},...
    'DiffusionNumber',{},...
    'SlicePos',{},...
    'SlcThk',{},...
    'PixelSpacing',{},...
    'StudyDescription',{},...
    'PatientID',{},...
    'Label',{});
% * Images are sorted into 3D via SlcLoc,
%   and 4D via arrayed values:
%       MRI - TE, TR, ...
%       CT  - kV, ...

% Read in all DICOM slices:
% hp = waitbar(0,'','Name','Loading DICOM image ...','WindowStyle','modal',...
%     'CreateCancelBtn','setappdata(gcbf,''canceling'',1)'); % Option to cancel load midway
% setappdata(hp,'canceling',0)
fprintf('Loading DICOM images from %u files\n',nf);
for ifn = 1:nf
    
    % Check for Cancel button press
    %     if getappdata(hp,'canceling')
    %         img = []; label = {}; fov = []; dcmdata = []; break
    %     end
    %     waitbar((ifn-1)/nf,hp,fname{ifn});
    fprintf('.');
    if mod(ifn,100)==0
        fprintf('\n')
    end
    
    % Load DICOM file info:
    tinfo = dicominfo(fullfile(fpath,fname{ifn}),'UseDictionaryVR',true);
    if (ifn==1) % Check manufacturer to read private tags:
        ddir = fileparts(which('cmi'));
        if isfield(tinfo,'Manufacturer')
            str = tinfo.Manufacturer;
        else
            str = '';
        end
        if strncmpi(str,'philips',7)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-Philips.txt'));
        elseif strncmpi(str,'ge',2)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-GE.txt'));
        elseif strncmpi(str,'siemens',7)
            dicomdict('set',fullfile(ddir,'read','dicom-dict-Siemens.txt'));
        else
            dicomdict('factory');
        end
        tinfo = dicominfo(fullfile(fpath,fname{ifn}),'UseDictionaryVR',true);
    end
    
    if isfield(tinfo,'Modality')
        % Check if Series already exists in structure:
        %     disp(tinfo.SeriesInstanceUID);
        %     disp(num2str(tinfo.AcquisitionNumber));
        %     disp(num2str(tinfo.SeriesNumber));
        %     disp(num2str(tinfo.InstanceNumber));
        %     waitforbuttonpress
        %         acqN = 0;
        %         if isfield(tinfo,'AcquisitionNumber') && ~isempty(tinfo.AcquisitionNumber)
        %             acqN = tinfo.AcquisitionNumber;
        %         end
        serN = 0;
        if isfield(tinfo,'SeriesNumber') && ~isempty(tinfo.SeriesNumber)
            serN = tinfo.SeriesNumber;
        end
        tempN = 0;
        if isfield(tinfo,'TemporalPositionIdentifier') && ~isempty(tinfo.TemporalPositionIdentifier)
            tempN = tinfo.TemporalPositionIdentifier;
        end
        diffN = 0;
        if isfield(tinfo,'DiffusionBValue')
            nv = length(tinfo.DiffusionBValue);
            if nv==1
                diffN = tinfo.DiffusionBValue;
            elseif isa(tinfo.DiffusionBValue,'uint8')
                diffN = str2double(char(tinfo.DiffusionBValue'));
            end
        elseif isfield(tinfo,'Private_DiffusionBValue')
            nv = length(tinfo.Private_DiffusionBValue);
            if nv==1
                diffN = tinfo.Private_DiffusionBValue;
            elseif isa(tinfo.Private_DiffusionBValue,'uint8')
                diffN = str2double(char(tinfo.Private_DiffusionBValue'));
            end
        elseif isfield(tinfo,'B_value') && (length(tinfo.B_value)==1)
            diffN = tinfo.B_value;
        elseif isfield(tinfo,'SlopInt_6_9') && ~isempty(tinfo.SlopInt_6_9)
            if isa(tinfo.SlopInt_6_9,'uint8')
                % stored as char
                diffN = char(tinfo.SlopInt_6_9');
                diffN = str2double(strtok(diffN,'\'));
                if diffN>1e6
                    diffN = diffN - 1e9;
                end
            else % assumed double
                diffN = tinfo.SlopInt_6_9(1);
            end
        end
        diffD = zeros(3,1);
        if isfield(tinfo,'DiffusionGradientOrientation')
            nv = length(tinfo.DiffusionGradientOrientation);
            if nv==3
                diffD = tinfo.DiffusionGradientOrientation;
            elseif isa(tinfo.DiffusionGradientOrientation,'uint8') && (nv>=24)
                diffD = [ typecast(tinfo.DiffusionGradientOrientation(1:8),'double') ;...
                    typecast(tinfo.DiffusionGradientOrientation(9:16),'double') ;...
                    typecast(tinfo.DiffusionGradientOrientation(17:24),'double') ];
            end
        elseif isfield(tinfo,'DiffusionGradientDirection') && (length(tinfo.DiffusionGradientDirection)==3)
            diffD = tinfo.DiffusionGradientDirection;
        elseif all(isfield(tinfo,{'DiffusionDirectionX','DiffusionDirectionY','DiffusionDirectionZ'}))
            if ~isempty(tinfo.DiffusionDirectionX) && (numel(tinfo.DiffusionDirectionX)==1)
                diffD(1) = tinfo.DiffusionDirectionX;
            end
            if ~isempty(tinfo.DiffusionDirectionY) && (numel(tinfo.DiffusionDirectionY)==1)
                diffD(2) = tinfo.DiffusionDirectionY;
            end
            if ~isempty(tinfo.DiffusionDirectionZ) && (numel(tinfo.DiffusionDirectionZ)==1)
                diffD(3) = tinfo.DiffusionDirectionZ;
            end
        end
        TE = 0;
        if isfield(tinfo,'EchoTime') && ~isempty(tinfo.EchoTime)
            TE = tinfo.EchoTime;
        end
        TR = 0;
        if isfield(tinfo,'RepetitionTime') && ~isempty(tinfo.RepetitionTime)
            TR = tinfo.RepetitionTime;
        end
        d = [tinfo.Rows,tinfo.Columns];

        j = [];
        if ~isempty(dcmdata)
            j = find( strcmp(tinfo.SeriesInstanceUID,{dcmdata(:).SeriesInstanceUID}) ...
                & (serN==[dcmdata(:).SeriesNumber]) ...
                & (tempN == [dcmdata(:).TemporalPositionIdentifier]) ...
                & (diffN == [dcmdata(:).DiffusionNumber]) ...
                & ismember([dcmdata(:).DiffusionDir]',diffD','rows')' ...
                & (TE==[dcmdata(:).TE]) ...
                & (TR==[dcmdata(:).TR]) ...
                & cellfun(@(x)all(x==[tinfo.Rows,tinfo.Columns]),{dcmdata.d}) ,1);
        end
        if isempty(j)
            % Initialize new series in structure:
            j = length(dcmdata)+1;
            val = '';
            if isfield(tinfo,'SeriesInstanceUID')
                val = tinfo.SeriesInstanceUID;
            end
            dcmdata(j).SeriesInstanceUID = val;
            dcmdata(j).SeriesNumber = serN;
            dcmdata(j).TemporalPositionIdentifier = tempN;
            dcmdata(j).DiffusionNumber = diffN;
            dcmdata(j).DiffusionDir = diffD;
            dcmdata(j).TE = TE;
            dcmdata(j).TR = TR;
            
            val = [1,1];
            if isfield(tinfo,'PixelSpacing')
                val = tinfo.PixelSpacing;
            end
            dcmdata(j).PixelSpacing = val;
            
            val = [];
            if isfield(tinfo,'SliceThickness')
                val = tinfo.SliceThickness;
            elseif isfield(tinfo,'SpacingBetweenSlices')
                val = abs(tinfo.SpacingBetweenSlices);
            end
            dcmdata(j).SlcThk = val;
            
            val = [1 0 0 0 1 0];
            if isfield(tinfo, 'ImageOrientationPatient')
                val = tinfo.ImageOrientationPatient;
            end
            dcmdata(j).Orient = val;
            
            
            val = '';
            if isfield(tinfo,'StudyDescription')
                val = tinfo.StudyDescription;
            end
            dcmdata(j).StudyDescription = val;
            
            if isfield(tinfo,'DiffusionBValue') && (length(tinfo.DiffusionBValue)==1)
                val = ['b',num2str(tinfo.DiffusionBValue)];
            elseif isfield(tinfo,'SeriesDescription') && ~isempty(tinfo.SeriesDescription)
                val = tinfo.SeriesDescription;
            elseif isfield(tinfo,'ProtocolName') && ~isempty(tinfo.ProtocolName)
                val = tinfo.ProtocolName;
            else
                val = tinfo.Modality;
            end
            dcmdata(j).Label = {val};
            
            val = '';
            if isfield(tinfo,'PatientIdentityRemoved') && strcmpi(tinfo.PatientIdentityRemoved,'yes') ...
                    && isfield(tinfo,'PatientName')
                if isfield(tinfo.PatientName,'FamilyName')
                    val = tinfo.PatientName.FamilyName;
                end
            elseif isfield(tinfo,'PatientID')
                val = tinfo.PatientID;
            elseif isfield(tinfo,'StudyID')
                val = tinfo.StudyID; % added this b/c some cases did not have PatientName tag in dicom
            end
            dcmdata(j).PatientID = val;
            
            val = '';
            if isfield(tinfo,'StudyDate')
                val = tinfo.StudyDate;
            end
            dcmdata(j).StudyDate = val;
            
            dcmdata(j).img = [];
            if all(isfield(tinfo,{'Rows','Columns'}))
                dcmdata(j).d = [tinfo.Rows,tinfo.Columns];
            end
        end
        k = size(dcmdata(j).SlicePos,1)+1;
        if ~isfield(tinfo,'AcquisitionNumber') || isempty(tinfo.AcquisitionNumber)
            val = 0;
        else
            val = tinfo.AcquisitionNumber;
        end
        dcmdata(j).AcquisitionNumber(k) = val;
        val = nan(1,3);
        if isfield(tinfo,'ImagePositionPatient')
            val = tinfo.ImagePositionPatient;
        elseif isfield(tinfo,'SliceLocation')
            val(3) = tinfo.SliceLocation;
        else
            val(3) = ifn;
        end
        dcmdata(j).SlicePos(k,:) = val;
        
        % Read slice data from file:
        ySlope = 1;
        if isfield(tinfo,'RescaleSlope') && ~isempty(tinfo.RescaleSlope)
            ySlope = tinfo.RescaleSlope;
        elseif isfield(tinfo,'MRScaleSlope')
            ySlope = 1/tinfo.MRScaleSlope;
        end
        yInt = 0;
        if isfield(tinfo,'RescaleIntercept') && ~isempty(tinfo.RescaleIntercept)
            yInt = tinfo.RescaleIntercept;
        elseif isfield(tinfo,'MRScaleIntercept')
            yInt = -tinfo.MRScaleIntercept/ySlope;
        end
        timg = ySlope * double(dicomread(tinfo)) + yInt;
        if strcmp(tinfo.Modality,'PT') && all(isfield(tinfo,{'AcquisitionTime',...
                'RadiopharmaceuticalInformationSequence','PatientWeight'}))
            if ifn==1
                warning('Converting raw PET image to SUV ...');
            end
            
            % Convert raw PET images to SUV
            t_acq = str2double(tinfo.AcquisitionTime);
            t_rad = str2double(tinfo.RadiopharmaceuticalInformationSequence.Item_1.RadiopharmaceuticalStartTime);
            half_life = tinfo.RadiopharmaceuticalInformationSequence.Item_1.RadionuclideHalfLife/ 60; % [min]
            total_dose = tinfo.RadiopharmaceuticalInformationSequence.Item_1.RadionuclideTotalDose;

            % Calculate SUV factor
            delta_time = (t_acq - t_rad) / 100; % [min]
            corrected_dose = total_dose * exp(- delta_time * log(2) / half_life); % [Bq] 
            timg = timg * tinfo.PatientWeight * 1000 / corrected_dose; % [g/Bq] = [] * [Kg]* 1000[g/kg] / [Bq]
        end
        if isfield(tinfo,'SamplesPerPixel') && tinfo.SamplesPerPixel>1
            % RGB data from ImBio
            timg = permute(timg,[1,2,4,3]);
        end
        if isfield(tinfo,'ImageType') && (length(tinfo.ImageType)>5) && strcmp(tinfo.ImageType(end-5:end),'MOSAIC')
            if isfield(tinfo,'LocationsInAcquisition')
                ns = int32(tinfo.LocationsInAcquisition(1));
            elseif isfield(tinfo,'AcquisitionMatrix')
                ns = prod([tinfo.Rows,tinfo.Columns]./tinfo.AcquisitionMatrix([1,4])');
            end
            nslab = ceil(sqrt(double(ns)));
            md = size(timg);
            d = md/nslab;
            mosi = timg;
            timg = zeros([d,ns]);
            ci = reshape((1:nslab)'*ones(1,nslab),1,[]);
            ri = reshape(ones(nslab,1)*(1:nslab),1,[]);
            for i = 1:ns
                timg(:,:,i) = mosi( (ri(i)-1)*d(1)+(1:d(1)) , (ci(i)-1)*d(2)+(1:d(2)) );
            end
            % Remove blank slices
            ind = squeeze(std(timg,0,[1,2]))>0;
            timg(:,:,~ind) = [];
            ns = nnz(ind);

            dcmdata(j).d = d;
            kk = k - 1 + (1:ns);
            dcmdata(j).AcquisitionNumber(kk) = dcmdata(j).AcquisitionNumber(k);
            % Correct slice locations:
            RS = reshape(tinfo.ImageOrientationPatient,[3,2]);
            t = dcmdata(j).SlicePos(k,:)' + RS*(double(md)-double(d))'/2;
            RS(:,3) = cross(RS(:,1),RS(:,2));
            th = double(0:ns-1)*dcmdata(j).SlcThk;
            dcmdata(j).SlicePos(kk,:) = repmat(t',[ns,1]) + (RS*[zeros(ns,2),th']')';
            k = kk;
        end
        if isempty(dcmdata(j).img)
            dcmdata(j).img = timg;
        else
            dcmdata(j).img(:,:,k,:) = timg;
        end
    end
end
% delete(hp);
fprintf('\n');

if ~isempty(dcmdata)
    
    %     % Some image sets not separable into 4D, so use multiples of slice
    %     % locations to determine splits (e.g. MR Solutions):
    %     if length(dcmdata)==1
    %         u = unique(cellfun(@(x)sum(dcmdata.SlcLoc==x),num2cell(unique(dcmdata.SlcLoc))));
    %         if (length(u)==1) && (u>1)
    %             ns = length(dcmdata.SlcLoc)/u;
    %             dcmdata.img = reshape(dcmdata.img,[dcmdata.d,ns,u]);
    %             dcmdata.SlcLoc = dcmdata.SlcLoc(1:ns);
    %             dcmdata.Label = repmat(dcmdata.Label,1,u);
    %         end
    %     end
    
    % Sort by slice location
    for i = 1:length(dcmdata)
        [~,ix] = sort(dcmdata(i).SlicePos(:,3));
        dcmdata(i).SlicePos = dcmdata(i).SlicePos(ix,:);
        dcmdata(i).img = dcmdata(i).img(:,:,ix);
        dcmdata(i).AcquisitionNumber = dcmdata(i).AcquisitionNumber(ix);
    end
    
    n = length(dcmdata);
    % If multiple images per position, try and separate based on AcquisitionNumber
    ct = 0;
    for i = 1:n
        ii = i+ct;
        ns = size(dcmdata(ii).SlicePos,1);
        uS = unique(dcmdata(ii).SlicePos,'rows');
        nuS = length(uS);
        uA = unique(dcmdata(ii).AcquisitionNumber);
        nuA = length(uA);
        if (nuA>1) && (nuA<ns) && (nuS~=ns)
            if (nuA>1)
                disp('Separating images by AcquisitionNumber');
                A = dcmdata(ii).AcquisitionNumber;
                uA = unique(A);
                nuA = length(uA);
                dcmdata = [ dcmdata(1:(ii-1)),...
                    repmat(dcmdata(ii),1,nuA),...
                    dcmdata((ii+1):end) ];
                for j = 1:nuA
                    ind = ~(A==uA(j));
                    dcmdata(ii-1+j).img(:,:,ind) = [];
                    dcmdata(ii-1+j).SlicePos(ind,:) = [];
                    dcmdata(ii-1+j).AcquisitionNumber(ind) = [];
                end
                ct = ct + nuA - 1;
            else
                disp('Separating images based on file order.');
                [~,ind] = sortrows(dcmdata(ii).SlicePos);
                nsep = ns/nuS;
                dcmdata = [ dcmdata(1:(ii-1)),...
                    repmat(dcmdata(ii),1,nsep),...
                    dcmdata((ii+1):end) ];
                for j = 1:nsep
                    jj = ii-1+j;
                    indj = ind(j:nsep:end);
                    dcmdata(jj).img = dcmdata(jj).img(:,:,indj);
                    dcmdata(jj).SlicePos = dcmdata(jj).SlicePos(indj,:);
                    dcmdata(jj).AcquisitionNumber = dcmdata(jj).AcquisitionNumber(indj);
                end
            end
        end
    end
    
    n = length(dcmdata);
    gflag = 0; % Flag for number of slices per location group
    oimg = [];
    uN = unique(cellfun(@(x)size(x,1),{dcmdata(:).SlicePos})); % Number of slices per set
    uS = unique(round(diff(dcmdata(1).SlicePos(:,3)),3));      % Spacing between slices for first set
    % Looking for significant differences in slice spacing:
    if (n==1) && (length(uS)<3) && ...
            ((mean(abs(uS-mean(uS))/mean(uS))>0.001) || any(sqrt(sum(diff(dcmdata.SlicePos,1,1).^2,2)) >= 2*dcmdata.SlcThk))
        % Case for 2-slice gapped CT data
        gflag = length(uS); % Number of slices per image section
        oimg = dcmdata.img;
        oloc = dcmdata.SlicePos;
    elseif (length(uN)==1) && ismember(uN,1:2)
        % 1: Case for single-slice gapped CT data
        % 2: Case for 2-slice gapped CT data
        gflag = numel(uS);
        oimg = cat(3,dcmdata(:).img);
        oloc = cat(1,dcmdata(:).SlicePos);
    elseif (n==1) && any(uS/dcmdata.SlcThk >= 2)
        % Case for single-slice gapped data not separated into diff vectors
        gflag = 1;
        oimg = dcmdata.img;
        oloc = dcmdata.SlicePos;
    end
    if gflag
        if ~noprompt
            gap_str = questdlg('How would you like to compile these slices?',...
                'Gapped CT','Concatenate','Insert Gaps','Cancel','Concatenate');
        end
        switch gap_str
            case 'Cancel'
                return;
            case 'Insert Gaps'
                tdata = dcmdata(1);
                
                % Determine fill value
                if noprompt
                    fval = 0;
                    imgmin = min(oimg,[],'all');
                    if imgmin<-1000
                        fval = imgmin;
                    end
                else
                    fval = str2double(inputdlg('Blank Slice Value:','',1,{'-1024'}));
                end
                
                % Determine gaps:
                [~,ix] = sort(oloc(:,3));
                dxyz = sqrt(sum(diff(oloc(ix,:),1).^2,2));
                d = size(oimg);
                if gflag == 2
                    dnew = floor((dxyz(1)+dxyz(2))/dxyz(1));
                    dz = abs(dxyz(1)+dxyz(2))/dnew;
                    d(3) = d(3)*dnew/2;
                    tmat = ones(d)*fval;
                    ind = round(dnew/2):dnew:d(3);
                    ind = [ind;ind+1];
                else % Single-slice
                    dnew = floor(dxyz(1)/tdata.SlcThk);
                    dz = abs(dxyz(1))/dnew;
                    d(3) = d(3)*dnew;
                    tmat = ones(d)*fval;
                    ind = round(dnew/2):dnew:d(3);
                end
                disp(['Image slices are now: ',num2str(ind(:)')])
                tmat(:,:,ind(:)) = oimg(:,:,ix);
                tacq = nan(1,d(3));
                tacq(ind) = tdata.AcquisitionNumber(ix);
                tdata.SlicePos = [interp1(ind,oloc(:,1),1:d(3),'linear','extrap')',...
                                  interp1(ind,oloc(:,2),1:d(3),'linear','extrap')',...
                                  interp1(ind,oloc(:,3),1:d(3),'linear','extrap')'];
                tdata.SlcThk = dz;
                tdata.img = tmat;
                tdata.AcquisitionNumber = tacq;
            otherwise
                tdata = dcmdata(1);
                tdata.img = oimg;
                tdata.SlicePos = oloc;
        end
        dcmdata = tdata;
    end
end

% User GUI to select single acquisition from set:
ndd = length(dcmdata);
if (ndd>1)
    dd = cellfun(@size,{dcmdata(:).img},'UniformOutput',false);
    ld = cellfun(@length,dd);
    if all(ld==ld(1)) && all(cellfun(@(x)all(x==dd{1}),dd))
        % Concatenate in 4D:
        dcmdata(1).img = cat(4,dcmdata(:).img);
        dcmdata(1).Label = [dcmdata(:).Label];
        dcmdata(1).AcquisitionNumber = ...
            reshape([dcmdata(:).AcquisitionNumber],size(dcmdata(1).img,3),[])';
        dcmdata(1).SeriesNumber = [dcmdata(:).SeriesNumber];
        dcmdata(1).TemporalPositionIdentifier = [dcmdata(:).TemporalPositionIdentifier];
        dcmdata(1).DiffusionNumber = [dcmdata(:).DiffusionNumber];
        dcmdata(1).DiffusionDir = [dcmdata(:).DiffusionDir];
        dcmdata(1).TE = [dcmdata(:).TE];
        dcmdata(1).TR = [dcmdata(:).TR];
        dcmdata(2:end) = [];
        %         elseif all(cellfun(@(x)all(x(1:2)==dd{1}(1:2)),dd))
        %             % Concatenate in 3D:
        %             dcmdata(1).img = cat(3,dcmdata(:).img);
        %             dcmdata(1).SlicePos = cat(1,dcmdata(:).SlicePos);
        %             dcmdata(1).AcquisitionNumber = cat(2,dcmdata(:).AcquisitionNumber);
        %             dcmdata(2:end) = [];
    else
        if noprompt
            answer = 1;
        else
            str = strcat('(',cellfun(@(x)num2str(size(x,1)),{dcmdata(:).SlicePos},...
                'UniformOutput',false),...
                ' Slices)',[dcmdata(:).Label]);
            % Show saggital preview for each:
            hf = figure('Colormap',gray);
            nrow = round(sqrt(ndd));
            ncol = ceil(ndd/nrow);
            for imont = 1:ndd
                subplot(nrow,ncol,imont),
                imshow(squeeze(max(dcmdata(imont).img,[],2)),[]);
                title(str{imont});
            end
            answer = listdlg('ListString',str,'SelectionMode','single',...
                'ListSize',[300,300]);
            delete(hf);
        end
        if isempty(answer)
            return % User cancelled the load
        else
            dcmdata = dcmdata(answer);
        end
    end
end

ind = isnan(dcmdata.SlicePos(:,3));
dcmdata.img(:,:,ind) = [];
dcmdata.SlicePos(ind,:) = [];

% Sort slices by location:
[d(1),d(2),d(3),d(4)] = size(dcmdata.img); d = double(d);
n4d = d(4);
uind = dcmdata.SlicePos(:,3);
[~,ix,~] = unique(uind,'rows');
ns = length(ix);
if ns~=d(3)
    % MR Solutions DICOMs have no way to separate out b-values of DWI
    if mod(d(3),ns)==0
        n4d =  d(3)/ns;
        uind = repmat(0:n4d-1,ns,1);
        uind = uind(:);
        ix = repmat(ix,n4d,1) + uind;
    else
        error('Matrix cannot be separated into 4D.')
    end
else
    dcmdata.img = dcmdata.img(:,:,ix,:);
    dcmdata.SlicePos = dcmdata.SlicePos(ix,:);
    dcmdata.AcquisitionNumber = dcmdata.AcquisitionNumber(:,ix);
end
if (n4d>1) && (d(3)==(n4d*nnz(uind==1)))
    ns = d(3)/n4d;
    dcmdata.img = reshape(dcmdata.img(:,:,ix),[d(1:2),ns,n4d]);
    dcmdata.SlicePos = dcmdata.SlicePos(ix(1:ns),:);
    % Determine labeling:
    dcmdata.Label = cell(1,n4d);
    ind = ix(1:ns:d(3));
    if isfield(dcmdata,'TR') && length(unique(dcmdata.TR))>1
        dcmdata.Label = strcat(dcmdata.Label,'TR=',...
            cellfun(@num2str,num2cell(dcmdata.TR(ind)),...
            'UniformOutput',false),'; ');
    end
    if isfield(dcmdata,'TE') && length(unique(dcmdata.TE))>1
        dcmdata.Label = strcat(dcmdata.Label,'TE=',...
            cellfun(@num2str,num2cell(dcmdata.TE(ind)),...
            'UniformOutput',false),'; ');
    end
    ind = cellfun(@isempty,dcmdata.Label);
    if any(ind)
        dcmdata.Label(ind) = cellfun(@num2str,num2cell(find(ind)),'UniformOutput',false);
    end
end

% Check for dimension match
[d(1),d(2),d(3),d(4)] = size(dcmdata.img); d = double(d);
if ~isempty(din) && ~all(d(1:3)==din)
    error(['Dimensions must match!',sprintf(' %f',d)])
end

% Calculate 3D orientation matrix (compatible with NIfTI orientation)
orient = [ [  dcmdata.Orient(1:3)*dcmdata.PixelSpacing(1) ,...
              dcmdata.Orient(4:6)*dcmdata.PixelSpacing(2) ,...
             (dcmdata.SlicePos(end,:)-dcmdata.SlicePos(1,:))'/(d(3)-1) ,...
              dcmdata.SlicePos(1,:)' ] ;...
              0 0 0 1];

% Prepare data to return:
img = dcmdata.img;
dcmdata = rmfield(dcmdata,'img');
info = struct('format','DICOM','meta',dcmdata);

fov = [dcmdata.PixelSpacing',1] .* d(1:3);
if size(dcmdata.SlicePos,1)>1
    fov(3) = abs(sqrt(sum(diff(dcmdata.SlicePos([1,end],:),1).^2,2))) * d(3)/(d(3)-1);
elseif ~isempty(dcmdata.SlcThk)
    fov(3) = d(3) * dcmdata.SlcThk;
end

label = dcmdata.Label;
end
