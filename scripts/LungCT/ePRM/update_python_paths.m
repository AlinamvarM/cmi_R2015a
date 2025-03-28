function python_path = update_python_paths(update_mode)
    % UPDATE_PYTHON_PATHS Find, store, and retrieve Python path for Clintrajan
    %
    % Usage:
    %   python_path = update_python_paths()     % Get existing path or set new one
    %   python_path = update_python_paths(true) % Force update path
    %   
    % Returns the Python path to use with Clintrajan functions
    
    % Default is to only update if needed
    if nargin < 1
        update_mode = false;
    end
    
    % If we're not in update mode, try to get existing path first
    if ~update_mode && ispref('Clintrajan', 'PythonPath')
        python_path = getpref('Clintrajan', 'PythonPath');
        
        % Verify the path still exists
        if exist(python_path, 'file')
            % Path exists, return it
            return;
        else
            fprintf('\nStored Python path no longer exists: %s\n', python_path);
            % Continue to update section
        end
    end
    
    % Find Python installations (built-in function)
    python_paths = findPythonInstallationsInternal();
    
    if isempty(python_paths)
        fprintf('\nNo Python installations found automatically.\n');
        custom_path = input('Please enter your Python executable path manually: ', 's');
        if ~isempty(custom_path) && exist(custom_path, 'file')
            python_path = custom_path;
        else
            error('Valid Python path is required to continue.');
        end
    else
        % Display found Python installations
        fprintf('\nFound %d Python installation(s):\n', length(python_paths));
        for i = 1:length(python_paths)
            fprintf('[%d] %s\n', i, python_paths{i});
        end
        
        % Let user choose which Python to use
        choice = input(sprintf('\nSelect Python installation [1-%d]: ', length(python_paths)));
        if isempty(choice) || choice < 1 || choice > length(python_paths)
            error('Invalid selection.');
        end
        
        python_path = python_paths{choice};
    end
    
    % Check required packages
    flag = checkRequiredPackages(python_path);
    % if checkRequiredPackages(python_path) == false
    %     proceed = input('\nDo you want to continue anyway? [y/N]: ', 's');
    %     if isempty(proceed) || lower(proceed(1)) ~= 'y'
    %         error('Required Python packages are missing. Setup cancelled.');
    %     end
    % end
    
    % SAVE THE PYTHON PATH FOR FUTURE USE
    setpref('Clintrajan', 'PythonPath', python_path);
    fprintf('\nPython path saved: %s\n', python_path);
    
    if flag
        fprintf('')
    else
        fprintf('You can now run the Clintrajan MATLAB functions with your selected Python.\n');
    end
end

function python_paths = findPythonInstallationsInternal()
    % Internal function to find Python installations
    python_paths = {};
    
    % Check by OS type
    if ispc  % Windows
        % Try system Python first
        [status, ~] = system('where python');
        if status == 0
            [status, result] = system('where python');
            paths = strsplit(strtrim(result), '\n');
            for i = 1:length(paths)
                if ~isempty(paths{i}) && exist(paths{i}, 'file')
                    python_paths{end+1} = strtrim(paths{i});
                end
            end
        end
        
        % Check common locations
        [~,userpath] = system('echo %USERPROFILE%'); userpath = strtrim(userpath);
        potential_paths = {
            'C:\Python*\python.exe',
            'C:\Program Files\Python*\python.exe',
            'C:\ProgramData\Anaconda*\python.exe',
            fullfile(userpath,'AppData\Local\Programs\Python\Python*\python.exe'),
            fullfile(userpath,'Anaconda*\python.exe'),
            fullfile(userpath,'.conda\envs\*\python.exe')
        };
        
        for i = 1:length(potential_paths)
            files = dir(potential_paths{i});
            for j = 1:length(files)
                if ~files(j).isdir
                    full_path = fullfile(files(j).folder, files(j).name);
                    python_paths{end+1} = full_path;
                end
            end
        end
    else  % macOS and Linux
        % Try system Python first using 'which'
        [status, ~] = system('which python');
        if status == 0
            [~, result] = system('which python');
            python_paths{end+1} = strtrim(result);
        end
        
        [status, ~] = system('which python3');
        if status == 0
            [~, result] = system('which python3');
            python_paths{end+1} = strtrim(result);
        end
        
        % Check Homebrew and Anaconda common locations on macOS
        if ismac
            potential_paths = {
                '/usr/bin/python*',
                '/usr/local/bin/python*',
                '/opt/homebrew/bin/python*',
                '/opt/anaconda*/bin/python',
                '/opt/miniconda*/bin/python',
                fullfile(getenv('HOME'), 'anaconda*/bin/python'),
                fullfile(getenv('HOME'), 'miniconda*/bin/python')
            };
            
            for i = 1:length(potential_paths)
                files = dir(potential_paths{i});
                for j = 1:length(files)
                    if ~files(j).isdir
                        full_path = fullfile(files(j).folder, files(j).name);
                        python_paths{end+1} = full_path;
                    end
                end
            end
        end
    end
    
    % Remove duplicates
    python_paths = unique(python_paths);
    
    % Verify paths actually work
    valid_paths = {};
    for i = 1:length(python_paths)
        if exist(python_paths{i}, 'file')
            cmd = sprintf('"%s" --version', python_paths{i});
            [status, ~] = system(cmd);
            if status == 0
                valid_paths{end+1} = python_paths{i};
            end
        end
    end
    
    python_paths = valid_paths;
end

function missing_flag = checkRequiredPackages(python_path)

    % Check for required Python packages
    required_packages = {'numpy', 'scipy', 'igraph', 'networkx', 'elpigraph',        'sklearn'};
    install_name =      {'numpy', 'scipy', 'igraph', 'networkx', 'elpigraph-python', 'scikit-learn'};
    np = numel(required_packages);
    missing_flag = false(1,np);
    
    fprintf('\nChecking for required Python packages...\n');
    
    for i = 1:np
        fprintf('  - %s : ',required_packages{i});

        cmd = sprintf('"%s" -c "import %s; print(''OK'')"', python_path, required_packages{i});
        [status, result] = system(cmd);
        
        if status ~= 0 || ~contains(result, 'OK')
            fprintf('missing\n');
            missing_flag(i) = true;
        else
            fprintf('found\n');
        end
    end
    
    for i = 1:np
        if missing_flag(i)
            if ispc
                missing_flag(i) = system(sprintf('"%s" -m pip install %s',python_path,install_name{i}));
            end
        end
    end

    missing_flag = any(missing_flag);

    % % Report missing packages
    % if ~isempty(missing_packages)
    %     fprintf('\nWARNING: The following required Python packages are missing:\n');
    %     for i = 1:length(missing_packages)
    %         fprintf('  - %s\n', missing_packages{i});
    %     end
    % 
    %     fprintf('\nTo install missing packages, run these commands:\n');
    %     for i = 1:length(missing_packages)
    %         package = missing_packages{i};
    %         install_name = package;
    % 
    %         % Handle special package names
    %         if strcmp(package, 'sklearn')
    %             install_name = 'scikit-learn';
    %         elseif strcmp(package, 'elpigraph')
    %             install_name = 'elpigraph-python';
    %         end
    % 
    %         fprintf('  %s -m pip install %s\n', python_path, install_name);
    %     end
    % 
    %     has_packages = false;
    % else
    %     fprintf('All required packages are installed.\n');
    %     has_packages = true;
    % end
end