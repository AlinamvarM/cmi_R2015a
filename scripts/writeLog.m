function writeLog(fn,str,varargin)

% write to command window
fprintf(str,varargin{:});

if ischar(fn)
    fn = {fn};
end

% write to log file
for i = 1:numel(fn)
    fni = fn{i};
    if ischar(fni) && endsWith(fni,{'.txt','.log'})
        fid = fopen(fni,'a');
        if fid>0
            fprintf(fid,str,varargin{:});
            fclose(fid);
        else
            fprintf('Could not open log file.\n');
        end
    end
end