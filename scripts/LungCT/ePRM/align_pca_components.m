function [score_aligned, score_case_aligned, coeff_aligned, flip_report] = align_pca_components(score, score_case, coeff, vox_pca)
    % Initialize output variables
    score_aligned = score;
    score_case_aligned = score_case;
    coeff_aligned = coeff;
    flip_report = struct('component', [], 'flipped', [], 'reason', {});
    
    % Determine number of components
    num_components = min(size(score, 2), size(vox_pca, 2));
    
    % Sample size for analysis
    sample_size = min(1000, min(size(score,1), size(vox_pca,1)));
    
    % Pre-compute all correlations and skewness values
    all_corr_matrix = zeros(num_components, num_components);
    all_skewness = struct('vox', zeros(1, num_components), 'curr', zeros(1, num_components));
    
    for i = 1:num_components
        all_skewness.vox(i) = skewness(vox_pca(1:sample_size, i));
        all_skewness.curr(i) = skewness(score(1:sample_size, i));
        
        for j = 1:num_components
            all_corr_matrix(i,j) = corr(score(1:sample_size, i), vox_pca(1:sample_size, j));
        end
    end
    
    % First pass: Handle PC1 and PC2 together
    for i = 1:2
        % Extract sample data
        vox_sample = vox_pca(1:sample_size, i);
        curr_sample = score(1:sample_size, i);
        
        % Compute key statistics
        vox_skew = all_skewness.vox(i);
        curr_skew = all_skewness.curr(i);
        
        % Check for significant skewness difference
        skew_diff = abs(vox_skew - curr_skew);
        sign_diff = sign(vox_skew) ~= sign(curr_skew);
        
        % Enhanced flipping criteria for PC1 and PC2
        should_flip = false;
        reason = '';
        
        if sign_diff && skew_diff > 0.5
            should_flip = true;
            reason = 'Opposite significant skewness';
        end
        
        % Stronger correlation threshold for PC1 and PC2
        if max(abs(all_corr_matrix(i,:))) > 0.7 && all_corr_matrix(i,i) < -0.3
            should_flip = true;
            reason = 'Strong negative correlation';
        end
        
        % Perform flipping if necessary
        if should_flip
            score_aligned(:, i) = -score(:, i);
            score_case_aligned(:, i) = -score_case(:, i);
            coeff_aligned(:, i) = -coeff(:, i);
            
            % Update correlation matrix after flip
            all_corr_matrix(i,:) = -all_corr_matrix(i,:);
            all_corr_matrix(:,i) = -all_corr_matrix(:,i);
            
            flip_report(i).component = i;
            flip_report(i).flipped = true;
            flip_report(i).reason = reason;
        else
            flip_report(i).component = i;
            flip_report(i).flipped = false;
            flip_report(i).reason = 'No flip needed';
        end
    end
    
    % Special handling for PC3
    i = 3;
    if i <= num_components
        % More conservative criteria for PC3
        vox_sample = vox_pca(1:sample_size, i);
        curr_sample = score_aligned(1:sample_size, i);
        
        % Compute correlation with PC1 and PC2 after their potential flips
        pc3_correlations = zeros(1, 2);
        for j = 1:2
            pc3_correlations(j) = corr(score_aligned(1:sample_size, i), vox_pca(1:sample_size, j));
        end
        
        % Only flip PC3 if there's very strong evidence
        should_flip = false;
        reason = '';
        
        % Check correlation with PC1 and PC2
        if mean(abs(pc3_correlations)) > 0.8 && all_corr_matrix(i,i) < -0.6
            should_flip = true;
            reason = 'Strong negative correlation with PC1/PC2';
        end
        
        % Additional validation check
        if should_flip
            % Temporarily flip PC3
            temp_score = score_aligned;
            temp_score(:, i) = -score_aligned(:, i);
            
            % Check if flipping improves overall alignment
            orig_alignment = mean(abs(corr(score_aligned(:,1:3), vox_pca(:,1:3))));
            new_alignment = mean(abs(corr(temp_score(:,1:3), vox_pca(:,1:3))));
            
            % Only keep the flip if it improves overall alignment
            if new_alignment > orig_alignment
                score_aligned(:, i) = -score_aligned(:, i);
                score_case_aligned(:, i) = -score_case_aligned(:, i);
                coeff_aligned(:, i) = -coeff_aligned(:, i);
                
                flip_report(i).component = i;
                flip_report(i).flipped = true;
                flip_report(i).reason = reason;
            else
                should_flip = false;
                reason = 'Flip would worsen overall alignment';
            end
        end
        
        if ~should_flip
            flip_report(i).component = i;
            flip_report(i).flipped = false;
            flip_report(i).reason = reason;
        end
    end
    
    % Print final alignment report
    fprintf('\nFinal Alignment Report:\n');
    for i = 1:num_components
        if flip_report(i).flipped
            fprintf('PC%d: Flipped - %s\n', i, flip_report(i).reason);
        else
            fprintf('PC%d: Not flipped - %s\n', i, flip_report(i).reason);
        end
    end
end