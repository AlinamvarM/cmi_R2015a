function T = compile_pipeline_results(basedir)

D = dir(fullfile(basedir,'batch*'));
for i = 1:numel(D)
    fn = fullfile(basedir,D(i).name,'Pipeline_Results.csv');
    t = readtable(fn);
    if i == 1
        T = t;
    else
        T = addtotable(T,t);
    end
end



function T = addtotable(T,t)

    nT = size(T,1);
    nt = size(t,1);
    ind_add = nT + (1:nt);
    vT = T.Properties.VariableNames;
    vt = t.Properties.VariableNames;

    % Add missing variables to T
    % ind = find(~ismember(vt,vT));
    for i = find(~ismember(vt,vT))
        if iscell(t.(vt{i}))
            tvar = repmat({''},nT,1);
        else
            tvar = nan(nT,1);
        end
        T.(vt{i}) = tvar;
    end
    
    % Add default rows to T
    vT = T.Properties.VariableNames;
    rdef = cell(1,numel(vT));
    for i = 1:numel(rdef)
        if iscell(T.(vT{i}))
            rdef{i} = '';
        else
            rdef{i} = nan;
        end
    end
    T = [T;repmat(rdef,nt,1)];

    % Add values in t to new rows in T
    for i = 1:numel(vt)
        T.(vt{i})(ind_add) = t.(vt{i});
    end












