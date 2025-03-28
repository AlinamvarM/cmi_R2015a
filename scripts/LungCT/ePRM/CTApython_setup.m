function [stat,envpath,err] = CTApython_setup()

stat = false;
envpath = '';
str = '';

% Find CTA Python environment
if ispc
    [~,userpath] = system('echo %USERPROFILE%');
else
    str = 'Not currently set up for non-Windows';
    warning(str);
    return;
end
envpath = fullfile(strtrim(userpath),'AppData','Roaming','MiTAP');
fn_env = fullfile(envpath,'.venv_CTA');
if isfile(fn_env)
    stat = true;
    return;
end

% Find and select Python installation
python_paths = findPythonInstallations();
if isempty(python_paths)
    [fn_py,path_py] = uigetfile('*.exe','Select Python executable');
    if fn_py
        python_path = fullfile(path_py,fn_py);
    else
        str = 'Python executable not found.'; return;
    end
else
    [indx,tf] = listdlg('ListString',python_paths,'SelectionMode','single');
    if tf
        python_path = python_paths{indx};
    else
        str = 'User canceled Python selection.'; return;
    end
end
    
% Create virtual environment
if ~isfolder(envpath)
    mkdir(envpath);
end
fn_mod = fullfile(envpath,'CTAsetup.py');



% % Get the current directory where all MATLAB files are located
%     current_dir = pwd;
% 
%     % Critical files that must be checked and updated
%     critical_files = {
%         'compute_tree_from_python.m',
%         'extract_trajectories_from_python.m',
%         'partition_data_from_python.m',
%         'project_on_tree_from_python.m',
%         'quantify_pseudotime_from_python.m',
%         'load_and_process_tree.m',
%         'PCApython.m',
%         'sadTier_v02.m',
%         'visualize_eltree_from_python'
%     };
% 
%     % Find these critical files recursively
%     critical_paths = findCriticalFiles(current_dir, critical_files);
% 
    
    
    % Check if required Python packages are installed
    required_packages = {'numpy', 'scipy', 'igraph', 'networkx', 'elpigraph', 'sklearn'};
    missing_packages = checkPythonPackages(python_path, required_packages);
    
    if ~isempty(missing_packages)
        fprintf('\nWARNING: The following required Python packages are missing:\n');
        for i = 1:length(missing_packages)
            fprintf('  - %s\n', missing_packages{i});
        end
        
        install_choice = input('Would you like to install the missing packages? [Y/n]: ', 's');
        if isempty(install_choice) || lower(install_choice(1)) == 'y'
            installPythonPackages(python_path, missing_packages);
        else
            fprintf('\nWARNING: Continuing without installing missing packages.\n');
            fprintf('         The MATLAB functions may not work correctly.\n');
            confirm = input('Are you sure you want to continue? [y/N]: ', 's');
            if isempty(confirm) || lower(confirm(1)) ~= 'y'
                fprintf('Operation cancelled by user.\n');
                return;
            end
        end
    end
    
    % Define patterns to match Python paths from any system
    path_patterns = {
        % Windows patterns
        'C:\\Users\\.*?\\anaconda\\python\.exe',
        'C:\\Users\\.*?\\Anaconda3\\python\.exe',
        'C:\\Users\\.*?\\miniconda3\\python\.exe',
        'C:\\anaconda\\python\.exe',
        'C:\\Anaconda3\\python\.exe',
        'C:\\miniconda3\\python\.exe',
        'C:\\Python.*?\\python\.exe',
        'C:\\Program Files\\Python.*?\\python\.exe',
        'C:\\Program Files (x86)\\Python.*?\\python\.exe',
        % Unix/Mac patterns
        '/Users/.*?/anaconda/bin/python',
        '/Users/.*?/Anaconda3/bin/python',
        '/Users/.*?/miniconda3/bin/python',
        '/opt/anaconda3/bin/python',
        '/opt/miniconda3/bin/python',
        '/usr/local/bin/python',
        '/usr/bin/python',
        '/usr/bin/python3',
        '/opt/homebrew/bin/python3',
        % Generic patterns
        'python\.exe',
        'python[23]?',
        % Command patterns
        'command\s*=\s*sprintf\s*\(\s*[''"].*?python.*?[''"]',
        'system\s*\(\s*[''"].*?python.*?[''"]',
        'pyenv\s*\(\s*''Version''\s*,\s*[''"].*?python.*?[''"]\s*,\s*''ExecutionMode''\s*,\s*''OutOfProcess''\s*\)',
        'pyenv\s*\(\s*''Version''\s*,\s*[''"].*?python\.exe.*?[''"]\s*,\s*''ExecutionMode''\s*,\s*''OutOfProcess''\s*\)',
        'pyenv\s*\(\s*''Version''\s*,\s*[^''"]*?python\.exe.*?[''"]\s*,\s*''ExecutionMode''\s*,\s*''OutOfProcess''\s*\)'
    };
    
    % Update critical files
    updateCriticalFiles(critical_paths, python_path, path_patterns);
    
    fprintf('\nPython paths have been updated successfully!\n');
    fprintf('You can now run the Clintrajan MATLAB functions with your selected Python.\n');
end

function python_paths = findPythonInstallations()
    python_paths = {};
    
    % Try to find Python in the system PATH
    if ispc
        [status, result] = system('where python');
        if status == 0
            paths = strsplit(strtrim(result), newline);
            python_paths = [python_paths, paths];
        end
    else
        [status, result] = system('which python3');
        if status == 0
            python_paths{end+1} = strtrim(result);
        end
        [status, result] = system('which python');
        if status == 0
            python_paths{end+1} = strtrim(result);
        end
    end
    
    % If not found in PATH, try common installation locations
    if ispc
        userprofile = getenv('USERPROFILE');
        potential_paths = {
            fullfile(userprofile, 'anaconda3', 'python.exe');...
            fullfile(userprofile, 'miniconda3', 'python.exe');...
            'C:\ProgramData\anaconda3\python.exe';...
            'C:\ProgramData\Anaconda3\python.exe';...
            'C:\Python39\python.exe';...
            'C:\Python38\python.exe';...
            'C:\Python37\python.exe'
        };
    else
        home_dir = getenv('HOME');
        potential_paths = {
            fullfile(home_dir, 'anaconda3', 'bin', 'python'),
            fullfile(home_dir, 'Anaconda3', 'bin', 'python'),
            fullfile(home_dir, 'miniconda3', 'bin', 'python'),
            '/opt/anaconda3/bin/python',
            '/opt/miniconda3/bin/python',
            '/usr/local/bin/python3',
            '/usr/bin/python3',
            '/opt/homebrew/bin/python3'
        };
    end
    
    % Check each potential path
    for i = 1:length(potential_paths)
        if exist(potential_paths{i}, 'file') && ~ismember(potential_paths{i}, python_paths)
            python_paths{end+1} = potential_paths{i};
        end
    end
    
    % Try to get conda environments
    try
        % Find conda executable
        conda_exe = '';
        if ispc
            for i = 1:length(python_paths)
                potential_conda = strrep(python_paths{i}, 'python.exe', 'Scripts\conda.exe');
                if exist(potential_conda, 'file')
                    conda_exe = potential_conda;
                    break;
                end
            end
        else
            for i = 1:length(python_paths)
                potential_conda = strrep(python_paths{i}, 'bin/python', 'bin/conda');
                if exist(potential_conda, 'file')
                    conda_exe = potential_conda;
                    break;
                end
            end
        end
        
        if ~isempty(conda_exe)
            % Get environment list
            [status, result] = system(['"' conda_exe '" env list']);
            if status == 0
                lines = strsplit(strtrim(result), newline);
                for i = 1:length(lines)
                    if ~startsWith(lines{i}, '#') && ~isempty(lines{i})
                        parts = strsplit(lines{i}, ' ');
                        env_path = strtrim(parts{end});
                        env_path = strrep(env_path, '*', '');
                        
                        if ispc
                            py_path = fullfile(env_path, 'python.exe');
                        else
                            py_path = fullfile(env_path, 'bin', 'python');
                        end
                        
                        if exist(py_path, 'file') && ~ismember(py_path, python_paths)
                            python_paths{end+1} = py_path;
                        end
                    end
                end
            end
        end
    catch
        % Ignore errors from conda command
    end
    
    % Try using MATLAB's Python
    try
        pyenv = pyenv;
        current_path = pyenv.Executable;
        if ~ismember(current_path, python_paths)
            python_paths{end+1} = current_path;
        end
    catch
        % Ignore errors from pyenv
    end
end

function missing_packages = checkPythonPackages(python_path, required_packages)
    missing_packages = {};
    
    fprintf('\nChecking required Python packages...\n');
    
    for i = 1:length(required_packages)
        package = required_packages{i};
        fprintf('  Checking for %s... ', package);
        
        % Create a temporary Python script to check if the package is installed
        temp_script = tempname;
        fid = fopen([temp_script '.py'], 'w');
        fprintf(fid, 'try:\n');
        fprintf(fid, '    import %s\n', package);
        fprintf(fid, '    print("OK")\n');
        fprintf(fid, 'except ImportError:\n');
        fprintf(fid, '    print("MISSING")\n');
        fclose(fid);
        
        % Run the script and check the output
        if ispc
            cmd = ['"' python_path '" "' temp_script '.py"'];
        else
            cmd = ['''' python_path ''' ''' temp_script '.py'''];
        end
        
        [status, result] = system(cmd);
        delete([temp_script '.py']);
        
        if status == 0 && contains(strtrim(result), 'OK')
            fprintf('OK\n');
        else
            fprintf('MISSING\n');
            missing_packages{end+1} = package;
        end
    end
end

function installPythonPackages(python_path, packages)
    % Get the conda or pip executable
    python_dir = fileparts(python_path);
    
    % Check if pip is available based on OS
    if ispc
        pip_path = fullfile(python_dir, 'Scripts', 'pip.exe');
        if ~exist(pip_path, 'file')
            pip_path = fullfile(python_dir, 'pip.exe');
        end
        
        % Use pip from the Python command if we couldn't find the pip executable
        if ~exist(pip_path, 'file')
            pip_command = ['"' python_path '" -m pip'];
        else
            pip_command = ['"' pip_path '"'];
        end
    else
        % On Unix systems, pip is usually in the same bin directory as python
        pip_path = fullfile(fileparts(python_dir), 'bin', 'pip');
        
        % Use pip from the Python command if we couldn't find the pip executable
        if ~exist(pip_path, 'file')
            pip_command = ['''' python_path ''' -m pip'];
        else
            pip_command = ['''' pip_path ''''];
        end
    end
    
    fprintf('\nInstalling missing packages...\n');
    
    % Install each missing package
    for i = 1:length(packages)
        package = packages{i};
        fprintf('  Installing %s... ', package);
        
        % Handle special cases for packages with different install names
        install_name = package;
        if strcmp(package, 'sklearn')
            install_name = 'scikit-learn';
        elseif strcmp(package, 'elpigraph')
        install_name = 'elpigraph-python';  % Changed from GitHub to PyPI package
        end
        
        % Install the package
        command = sprintf('%s install %s', pip_command, install_name);
        [status, ~] = system(command);
        
        if status == 0
            fprintf('SUCCESS\n');
        else
            fprintf('FAILED\n');
            fprintf('    Try installing manually with: %s\n', command);
        end
    end
end

function critical_paths = findCriticalFiles(rootPath, targetFiles)
    critical_paths = {};
    
    % Recursively search for matching files
    for i = 1:length(targetFiles)
        [~, name, ext] = fileparts(targetFiles{i});
        filename = [name, ext];
        
        % Find all instances of this file recursively
        foundFiles = dir(fullfile(rootPath, '**', filename));
        
        % Add all found paths to our list
        for j = 1:length(foundFiles)
            full_path = fullfile(foundFiles(j).folder, foundFiles(j).name);
            critical_paths{end+1} = full_path;
        end
    end
end

function updateCriticalFiles(critical_files, python_path, path_patterns)
    for i = 1:length(critical_files)
        file_path = critical_files{i};
        
        % Read the file
        fid = fopen(file_path, 'r');
        if fid == -1
            continue;
        end
        
        % Read all lines
        content = fread(fid, '*char')';
        fclose(fid);
        
        % Process each line to handle different Python path formats
        lines = strsplit(content, newline);
        updated = false;
        
        for j = 1:length(lines)
            line = lines{j};
            
            % Check for Python paths using patterns
            for k = 1:length(path_patterns)
                [start_idx, end_idx] = regexp(line, path_patterns{k});
                
                for m = 1:length(start_idx)
                    % Extract the matched path and its context
                    matched_text = line(start_idx(m):end_idx(m));
                    
                    % Determine the replacement based on context
                    if contains(matched_text, 'pyenv')
                        if ispc
                            % For Windows, preserve backslashes in the path
                            new_line = regexprep(line, 'pyenv\s*\(\s*''Version''\s*,\s*[''"].*?[''"]\s*,\s*''ExecutionMode''\s*,\s*''OutOfProcess''\s*\)', ['pyenv(''Version'', ''' strrep(python_path, '\', '\\') ''', ''ExecutionMode'', ''OutOfProcess'')']);
                        else
                            new_line = regexprep(line, 'pyenv\s*\(\s*''Version''\s*,\s*[''"].*?[''"]\s*,\s*''ExecutionMode''\s*,\s*''OutOfProcess''\s*\)', ['pyenv(''Version'', ''' python_path ''', ''ExecutionMode'', ''OutOfProcess'')']);
                        end
                    elseif contains(matched_text, 'system')
                        if ispc
                            new_line = regexprep(line, 'system\s*\(\s*[''"].*?python.*?[''"]', ['system("' strrep(python_path, '\', '\\') '"']);
                        else
                            new_line = regexprep(line, 'system\s*\(\s*[''"].*?python.*?[''"]', ['system(''\''' python_path '\''']);
                        end
                    elseif contains(matched_text, 'sprintf')
                        if ispc
                            new_line = regexprep(line, 'sprintf\s*\(\s*[''"].*?python.*?[''"]', ['sprintf("' strrep(python_path, '\', '\\') '"']);
                        else
                            new_line = regexprep(line, 'sprintf\s*\(\s*[''"].*?python.*?[''"]', ['sprintf(''\''' python_path '\''']);
                        end
                    else
                        % Handle direct path replacement
                        if ispc
                            new_line = regexprep(line, '[A-Z]:\\.*?python\.exe', strrep(python_path, '\', '\\'));
                        else
                            new_line = regexprep(line, '/.*?/python[23]?', python_path);
                        end
                    end
                    
                    % Update the line if it was changed
                    if ~strcmp(line, new_line)
                        lines{j} = new_line;
                        updated = true;
                        break;
                    end
                end
                
                if updated
                    break;
                end
            end
        end
        
        % Write back if updated
        if updated
            % Join lines back together
            new_content = strjoin(lines, newline);
            
            % Write the modified content back to the file
            fid = fopen(file_path, 'w');
            if fid ~= -1
                fprintf(fid, '%s', new_content);
                fclose(fid);
            end
        end
    end
end