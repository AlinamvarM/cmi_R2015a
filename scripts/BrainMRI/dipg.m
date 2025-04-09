function T = dipg(C)

    % Initialize data paths
    p.base_path = 'R:\CGalban_Lab\Cancer\DMG_DIPG\20230930_BLau';
    p.raw_path = fullfile(p.base_path,'RawData');
    p.procdir = 'R:\CGalban_Lab\LabMembers\BenHoff\tempDATA\DIPG\Proc3';
    p.voidir = 'R:\CGalban_Lab\Cancer\DMG_DIPG\20230930_BLau\RawData\tumorVOI';
    
    % Define primary image tags and secondary for registrations
    p.NNtag = {'ADC','SynthSeg','VOI'}; % Images with these tags will be interpolated using nearest neighbor instead of linear
    p.img_tree = {{'T2w','T2w.SynthSeg'};...
                  {'DWI','ADC'};...
                  {'FLAIR','FLAIR.tumorVOI'};...
                  {'FLAIR_post','FLAIR_post.tumorVOI'}};
    p.cmi = CMIclass;
    p.cmi.img.prm.setOpts('thresh',[2,3,1,-.55; 2,3,1,.55],...
                          'prmmap',{[false false], 'ADC_-';...
                                    [true  false], 'ADC_0';...
                                    [true  true], 'ADC_+'},...
                          'cutoff',[2,0.0001,3 ; 3,0.0001,3],...
                          'cmap',flip(eye(3)),...
                          'statchk',false);

    % Read catalog
    if nargin<1
        cat_path = fullfile(p.raw_path,'Pipeline_catalog.xlsx');
        C = readtable(cat_path);
        if isnumeric(C.StudyDate)
            C.StudyDate = arrayfun(@num2str,C.StudyDate,'UniformOutput',false);
        end
    end
    
    % Determine subjects in catalog
    [ID,~,ic] = unique(C.UMlabel);
    
    % Loop over subjects
    T = [];
    for i = 1:numel(ID)
        t = dipg_subj(ID{i},C(ic==i,:),p);
        T = addResultToTable(T,t);
    end

    % Delete CMIclass object
    p.cmi.delete;

    % Write results to study folder
    if ~isempty(T)
        writetable(T,fullfile(p.procdir,'DIPG.AllResults.xlsx'));
    end

function T = dipg_subj(ID,C,p)
% Processing for each subject

    subj_path = fullfile(p.procdir,ID);
    if ~isfolder(subj_path)
        mkdir(subj_path);
    end
    p.regdir = fullfile(p.procdir,ID,'reg');
    if ~isfolder(p.regdir)
        mkdir(p.regdir);
    end

    % Find timepoints
    [utp,~,ic] = unique(C.StudyDate);

    % Loop over time points
    T = [];
    p.fn_ref = ''; % Baseline TP scan to register to
    for itp = 1:numel(utp)
        t = [];
        try
            [t,p] = dipg_case(ID,utp{itp},C(ic==itp,:),p);
        catch err
            fprintf('Case failed: %s\n%s',[ID,'_',utp{itp}],getReport(err,"extended"))
        end
        if ~isempty(t)
            T = addResultToTable(T,t);
        end
    end

    % Save fDM plot over time
    if ~isempty(T) && istable(T) && all(ismember({'fDM-','fDM0','fDM+'},T.Properties.VariableNames))
        dt = datetime(T.StudyDate,'InputFormat','yyyyMMdd');
        dt = days(dt-min(dt));
        hf = figure; ha = axes(hf);
        plot(dt,T.("fDM-"),'-*b',dt,100-T.fDM0,'-*g',dt,T.("fDM+"),'-*r','LineWidth',2);
        xlabel(ha,'Days');
        ylabel(ha,'% Tumor Volume');
        legend(ha,'fDM-','100-fDM0','fDM+',"Location",'northwest');
        print(hf,'-dtiff',fullfile(p.regdir,[ID,'.fDMtimeplot.tif']));
        delete(hf);
    end

    % Collect fDM figures for montage
    fn = dir(fullfile(p.regdir,'*.PRMoverlay.Slice*.tif'));
    N = numel(fn);
    if N
        % Set up images:
        hf = figure; ha = axes(hf,'Units','pixels');
        img_in = cell(1,N);
        for i = 1:N
            timg = imread(fullfile(p.regdir,fn(i).name));
            imshow(timg,'Parent',ha);
            text(ha,mean(ha.XLim),0.03*diff(ha.YLim),extractBefore(fn(i).name,'.'),...
                'FontSize',18,'Color','y','FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
            pos = tightPosition(ha);
            F = getframe(hf,[pos(1:2)+1,pos(3:4)-2]);
            img_in{i} = F.cdata;
        end
        r = round(sqrt(3*N/4));
        timg = imtile(img_in,'GridSize',[r NaN]);
        imwrite(timg,fullfile(p.regdir,[ID,'.fDMmontage.tif']));
    end

    % Save table to subject folder:
    if ~isempty(T)
        writetable(T,fullfile(subj_path,[ID,'.Results.xlsx']));
    end



% function T = addToTable(T,t)
% % T = addTableVarVal(T,t)
% %   Inputs: T - table to add values to
% %           t - table to add to T
% % T = addTableVarVal(T,varname,regionstr,vals)
% %   Inputs: T - table to add values to
% %           varname     - variable name
% %           regionstr   - name of segmentation region
% %           val         - value of input
%     if isempty(T)
%         T = t;
%     else
% 
%     end
% 
%     if nargin==2 && istable(varargin{1}) && any(strcmp(varargin{1}.Properties.VariableNames,'ROI'))
%         vals = varargin{1};
%         regionstr = vals.ROI;
%         vals = removevars(vals,'ROI');
%         varstr = vals.Properties.VariableNames;
%     elseif nargin==4
%         varstr = varargin{1};
%         regionstr = varargin{2};
%         vals = varargin{3};
%         if ischar(regionstr)
%             regionstr = {regionstr};
%         end
%         if ischar(varstr)
%             varstr = {varstr};
%         end
%         if numel(varstr)<size(vals,2)
%             varstr = strcat(varstr,'_',cellfun(@num2str,num2cell(1:size(vals,2)),'UniformOutput',false));
%         end
%     else
%         return;
%     end
%     if numel(regionstr)==size(vals,1)
%         % Table T must have RowNames set to ROI
%         if isempty(T.Properties.RowNames)
%             T.Properties.RowNames = T.ROI;
%         end
%         for i = 1:numel(varstr)
%             if istable(vals)
%                 tvals = vals.(varstr{i});
%             else
%                 tvals = vals(:,i);
%             end
%             if iscell(tvals)
%                 defval = {''};
%             elseif isnumeric(tvals)
%                 defval = nan;
%             else
%                 defval = {[]};
%             end
%             if ~ismember(varstr{i},T.Properties.VariableNames)
%                 T = addvars(T,repmat(defval,size(T,1),1),'NewVariableNames',varstr(i));
%             end
%             T.(varstr{i})(regionstr) = tvals;
%         end
%     end
    