function analyze_feature_along_trajectories(PseudoTimeTraj, tree_elpi, ProjStruct, finalCTAtable, feature_name, homepwd)
% ANALYZE_FEATURE_ALONG_TRAJECTORIES Analyzes a feature's values along elastic tree trajectories
%
% Inputs:
%   PseudoTimeTraj - Cell array of trajectory structures
%   tree_elpi - Elastic tree structure
%   ProjStruct - Projection structure
%   finalCTAtable - Table containing feature data
%   feature_name - Name of the feature to analyze (e.g., 'fsad.v')
%   homepwd - Home directory for saving results
%
% This function creates visualizations of the specified feature along each trajectory,
% showing both the feature values vs pseudotime and the points projected onto the tree.

% Find the feature in your data
feature_idx = find(contains(finalCTAtable.Properties.VariableNames, feature_name, 'IgnoreCase', true));

if ~isempty(feature_idx)
    fprintf('Analyzing %s along trajectories\n', feature_name);
    
    % Create a figure for each trajectory
    for traj_idx = 1:length(PseudoTimeTraj)
        traj = PseudoTimeTraj{traj_idx};
        
        % Get points, pseudotime, and path for this trajectory
        points = traj.Points + 1; % Convert from 0-based to 1-based
        pseudotime = traj.Pseudotime;
        path = traj.Trajectory;
        
        % Filter to include only points within your dataset
        valid_indices = points <= size(finalCTAtable, 1);
        points = points(valid_indices);
        pseudotime = pseudotime(valid_indices);
        
        if length(points) < 5
            fprintf('  Trajectory %d (%d→%d): Not enough points (%d)\n', traj_idx, path(1), path(end), length(points));
            continue;
        end
        
        % Get feature values for these points
        feature_values = finalCTAtable{points, feature_idx};
        
        % Remove NaN values
        valid_data = ~isnan(feature_values);
        x = pseudotime(valid_data);
        y = feature_values(valid_data);
        
        if length(x) < 5
            fprintf('  Trajectory %d (%d→%d): Not enough valid points after NaN removal (%d)\n', traj_idx, path(1), path(end), length(x));
            continue;
        end
        
        % Create figure
        figure('Position', [100, 100, 1000, 700]);
        
        % Create subplot for scatterplot with regression
        subplot(2, 1, 1);
        scatter(x, y, 40, y, 'filled', 'MarkerEdgeColor', 'k');
        colormap('jet');
        colorbar;
        hold on;
        
        % Sort data for smooth line plotting
        [x_sorted, sort_idx] = sort(x);
        y_sorted = y(sort_idx);
        
        % Try to fit a smooth curve if enough points
        if length(x) >= 10
            try
                % Fit a smoothing spline
                smoothing_param = 0.5; % Adjust between 0 and 1 (higher = smoother)
                fit_obj = fit(x_sorted, y_sorted, 'smoothingspline', 'SmoothingParam', smoothing_param);
                
                % Create smooth curve
                x_fine = linspace(min(x), max(x), 100);
                y_fine = feval(fit_obj, x_fine);
                
                % Plot the smooth curve
                plot(x_fine, y_fine, 'k-', 'LineWidth', 2);
                
                % Calculate R²
                y_pred = feval(fit_obj, x);
                SST = sum((y - mean(y)).^2);
                SSE = sum((y - y_pred).^2);
                R2 = 1 - SSE/SST;
                
                title(sprintf('Trajectory %d: %s vs Pseudotime (R² = %.3f)', traj_idx, feature_name, R2));
            catch
                % If curve fitting fails, just connect the points
                plot(x_sorted, y_sorted, 'k-', 'LineWidth', 1.5);
                title(sprintf('Trajectory %d: %s vs Pseudotime', traj_idx, feature_name));
            end
        else
            % If too few points, just connect the points
            plot(x_sorted, y_sorted, 'k-', 'LineWidth', 1.5);
            title(sprintf('Trajectory %d: %s vs Pseudotime', traj_idx, feature_name));
        end
        
        xlabel('Pseudotime');
        ylabel(feature_name);
        grid on;
        
        % Create subplot for visualizing points on tree
        subplot(2, 1, 2);
        
        % Get node positions and edges
        NodePositions = tree_elpi.NodePositions;
        Edges = tree_elpi.Edges;
        
        % Plot the tree edges
        hold on;
        for i = 1:size(Edges, 1)
            node1 = Edges(i, 1) + 1; % 0-indexed to 1-indexed
            node2 = Edges(i, 2) + 1;
            
            % Plot edge
            line([NodePositions(node1, 1), NodePositions(node2, 1)], ...
                 [NodePositions(node1, 2), NodePositions(node2, 2)], ...
                 'LineWidth', 1.5, 'Color', [0.7, 0.7, 0.7]);
        end
        
        % Highlight the trajectory path
        path_edges = traj.Trajectory_Edges;
        for i = 1:length(path_edges)
            edge_idx = path_edges(i) + 1; % 0-indexed to 1-indexed
            if edge_idx <= size(Edges, 1)
                node1 = Edges(edge_idx, 1) + 1;
                node2 = Edges(edge_idx, 2) + 1;
                
                % Plot highlighted edge
                line([NodePositions(node1, 1), NodePositions(node2, 1)], ...
                     [NodePositions(node1, 2), NodePositions(node2, 2)], ...
                     'LineWidth', 3, 'Color', 'r');
            end
        end
        
        % Get projection information from ProjStruct for these points
        proj_values = ProjStruct.ProjectionValues(points);
        edge_ids = ProjStruct.EdgeID(points);
        
        % Compute the projected points on the tree
        projected_points = zeros(length(points), 2);
        for i = 1:length(points)
            if edge_ids(i) >= 0 && edge_ids(i) < size(Edges, 1)
                % Get the edge endpoints
                node1 = Edges(edge_ids(i)+1, 1) + 1;
                node2 = Edges(edge_ids(i)+1, 2) + 1;
                
                % Get projection value
                t = proj_values(i);
                
                % Compute the point on the edge
                p1 = NodePositions(node1, 1:2);
                p2 = NodePositions(node2, 1:2);
                
                % Linear interpolation
                projected_points(i, :) = (1-t) * p1 + t * p2;
            end
        end
        
        % Plot tree nodes
        scatter(NodePositions(:,1), NodePositions(:,2), 30, 'k', 'filled');
        
        % Plot the points with feature values
        scatter(projected_points(:,1), projected_points(:,2), 40, feature_values, 'filled', 'MarkerEdgeColor', 'k');
        colormap('jet');
        colorbar;
        
        % Customize plot
        title(sprintf('Trajectory %d: Path %d → %d', traj_idx, path(1), path(end)));
        grid on;
        axis equal;
        
        % Save the figure
        saveas(gcf, fullfile(homepwd, 'results', sprintf('%s_traj%d_analysis.png', feature_name, traj_idx)));
        
        % Close the figure to avoid memory issues
        close;
    end
    
    % Create a combined visualization with all trajectories
    figure('Position', [100, 100, 1200, 900], 'Color', [0.9, 0.9, 0.9]);
    
    % Get node positions and edges
    NodePositions = tree_elpi.NodePositions;
    Edges = tree_elpi.Edges;
    
    % Plot the tree edges
    hold on;
    for i = 1:size(Edges, 1)
        node1 = Edges(i, 1) + 1;
        node2 = Edges(i, 2) + 1;
        line([NodePositions(node1, 1), NodePositions(node2, 1)], ...
             [NodePositions(node1, 2), NodePositions(node2, 2)], ...
             'LineWidth', 1.5, 'Color', [0.7, 0.7, 0.7]);
    end
    
    % Plot tree nodes
    scatter(NodePositions(:,1), NodePositions(:,2), 30, 'k', 'filled');
    
    % Use different colors for each trajectory
    colors = lines(length(PseudoTimeTraj));
    
    % Plot each trajectory
    legend_entries = {};
    for traj_idx = 1:length(PseudoTimeTraj)
        traj = PseudoTimeTraj{traj_idx};
        
        % Skip if no path
        if isempty(traj.Trajectory_Edges)
            continue;
        end
        
        % Highlight the trajectory path
        path_edges = traj.Trajectory_Edges;
        for i = 1:length(path_edges)
            edge_idx = path_edges(i) + 1;
            if edge_idx <= size(Edges, 1)
                node1 = Edges(edge_idx, 1) + 1;
                node2 = Edges(edge_idx, 2) + 1;
                
                % Plot highlighted edge with trajectory-specific color
                h = line([NodePositions(node1, 1), NodePositions(node2, 1)], ...
                      [NodePositions(node1, 2), NodePositions(node2, 2)], ...
                      'LineWidth', 3, 'Color', colors(traj_idx,:));
                
                % Only add to legend once
                if i == 1
                    legend_entries{end+1} = sprintf('Traj %d: %d → %d', traj_idx, traj.Trajectory(1), traj.Trajectory(end));
                end
            end
        end
    end
    
    % Add legend
    if ~isempty(legend_entries)
        legend(legend_entries, 'Location', 'best');
    end
    
    % Customize plot
    title('All Trajectories', 'FontSize', 14, 'FontWeight', 'bold');
    grid on;
    axis equal;
    
    % Save the figure
    saveas(gcf, fullfile(homepwd, 'results', 'all_trajectories.png'));
else
    warning('Feature %s not found in finalCTAtable', feature_name);
end
end