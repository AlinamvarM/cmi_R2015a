function T = compile_catalogs(fn)

if ~nargin
    % Looks in first subfolders for batch catalogs
    fn = dir(fullfile(pwd,'*\Pipeline_catalog.csv'));
    fn = fullfile({fn.folder},{fn.name});
end

warning('off','MATLAB:table:RowsAddedExistingVars');

T = table(); N = 0;
for i = 1:numel(fn)
    fprintf('%s ... ',fn{i});
    t = readtable(fn{i});
    [nr,nc] = size(t);
    vnt = t.Properties.VariableNames;
    vnT = T.Properties.VariableNames;
    for j = 1:nc
        vnj = vnt{j};
        if ismember(vnj,vnT)
            csT = iscell(T.(vnj));
            cst = iscell(t.(vnj));
            if csT && ~cst
                t.(vnj) = cellfun(@num2str,num2cell(t.(vnj)),'UniformOutput',false);
            elseif cst && ~csT
                T.(vnj) = cellfun(@num2str,num2cell(T.(vnj)),'UniformOutput',false);
            end
        end
        T.(vnj)(N+(1:nr)) = t.(vnj);
    end
    fprintf('done\n');
    N = N+nr;
end

warning('on','MATLAB:table:RowsAddedExistingVars');
