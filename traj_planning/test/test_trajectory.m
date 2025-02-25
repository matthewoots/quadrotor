clear all
close all

load('simple.mat');

clear path;

path{1}(1,:) = [0, -4.9, 0.2];
path{1}(2,:) = [-5, 5, 0.2];
path{1}(3,:) = [5, 10, 0.2];
path{1}(4,:) = [6, 17, 5];

trajectory_generator([], [], map, path);

% TEST_TRAJECTORY simulates the robot from START to STOP following a PATH
% that's been planned for MAP.
% start - a 3d vector or a cell contains multiple 3d vectors
% stop  - a 3d vector or a cell contains multiple 3d vectors
% map   - map generated by your load_map
% path  - n x 3 matrix path planned by your dijkstra algorithm
% vis   - true for displaying visualization

%Controller and trajectory generator handles
controlhandle = @controller;
trajhandle    = @trajectory_generator;

% Make cell
if ~iscell(start), start = {start}; end
if ~iscell(stop),  stop  = {stop}; end
if ~iscell(path),  path  = {path} ;end

% Get nquad
nquad = length(start);

% Make column vector
for qn = 1:nquad
    start{qn} = start{qn}(:);
    stop{qn} = stop{qn}(:);
end

% Quadrotor model
params = crazyflie();

%% **************************** FIGURES *****************************
% Environment figure
vis = true;


fprintf('Initializing figures...\n')
if vis
    h_fig = figure('Name', 'Environment');
else
    h_fig = figure('Name', 'Environment', 'Visible', 'Off');
end
if nquad == 1
    plot_path(map, path{1});
else
    % you could modify your plot_path to handle cell input for multiple robots
end
h_3d = gca;
drawnow;
xlabel('x [m]'); ylabel('y [m]'); zlabel('z [m]')
quadcolors = lines(nquad);
set(gcf,'Renderer','OpenGL')

%% *********************** INITIAL CONDITIONS ***********************
fprintf('Setting initial conditions...\n')
% Maximum time that the quadrotor is allowed to fly
time_tol = 30;          % maximum simulation time
starttime = 0;          % start of simulation in seconds
tstep     = 0.01;       % this determines the time step at which the solution is given
cstep     = 0.05;       % image capture time interval
nstep     = cstep/tstep;
time      = starttime;  % current time
max_iter  = time_tol / cstep;      % max iteration
for qn = 1:nquad
    % Get start and stop position
    x0{qn}    = init_state(start{qn}, 0);
    xtraj{qn} = zeros(max_iter*nstep, length(x0{qn}));
    ttraj{qn} = zeros(max_iter*nstep, 1);
end

% Maximum position error of the quadrotor at goal
pos_tol  = 0.05; % m
% Maximum speed of the quadrotor at goal
vel_tol  = 0.05; % m/s

x = x0;        % state

%% ************************* RUN SIMULATION *************************
OUTPUT_TO_VIDEO = 0;
if OUTPUT_TO_VIDEO == 1
    v = VideoWriter('map1.avi');
    open(v)
end

desState = zeros(3,max_iter);

fprintf('Simulation Running....\n')
for iter = 1:max_iter
    timeint = time:tstep:time+cstep;
    tic;
    % Iterate over each quad
    for qn = 1:nquad
        % Initialize quad plot
        if iter == 1
            QP{qn} = QuadPlot(qn, x0{qn}, 0.1, 0.04, quadcolors(qn,:), max_iter, h_3d);
            desired_state = trajhandle(time, qn);
            QP{qn}.UpdateQuadPlot(x{qn}, [desired_state.pos; desired_state.vel], time);
            h_title = title(sprintf('iteration: %d, time: %4.2f', iter, time));
        end

        % Run simulation
        [tsave, xsave] = ode45(@(t,s) quadEOM(t, s, qn, controlhandle, trajhandle, params), timeint, x{qn});
        x{qn} = xsave(end, :)';
        % Save to traj
        xtraj{qn}((iter-1)*nstep+1:iter*nstep,:) = xsave(1:end-1,:);
        ttraj{qn}((iter-1)*nstep+1:iter*nstep)   = tsave(1:end-1);

        map0 = map;
        path0 = path;
        [ts, total_time] = generate_ts(path{1});
        path{1}
        X = traj_opt3(path{1}, total_time,ts);
       
        p = path{qn};
        if (time + cstep) >= total_time
            pos = p(end,:);
            vel = [0;0;0];
            acc = [0;0;0];
        else
        %     
        %     3rd order trajectory planning
        k = find(ts<=(time + cstep));
        k = k(end);
        pos = [(time + cstep)^3, (time + cstep)^2, (time + cstep), 1]*X(4*(k-1)+1:4*k,:);
        vel = [3*(time + cstep)^2, 2*(time + cstep), 1, 0]*X(4*(k-1)+1:4*k,:);
        acc = [6*(time + cstep), 2, 0, 0]*X(4*(k-1)+1:4*k,:);
        end

        yaw = 0;
        yawdot = 0;

        % =================== Your code ends here ===================

        desired_state.pos = pos(:);
        desired_state.vel = vel(:);
        desired_state.acc = acc(:);
        desired_state.yaw = yaw;
        desired_state.yawdot = yawdot;
        
        
        % Update quad plot
        desState(:,iter) = transpose(desired_state.pos);
        
        QP{qn}.UpdateQuadPlot(x{qn}, [desired_state.pos; desired_state.vel], time + cstep);
        if OUTPUT_TO_VIDEO == 1
            im = frame2im(getframe(gcf));
            writeVideo(v,im);
        end
    end

    set(h_title, 'String', sprintf('iteration: %d, time: %4.2f', iter, time + cstep))
    time = time + cstep; % Update simulation time
    t = toc;

    % Pause to make real-time
    if (t < cstep)
        pause(cstep - t);
    end

    % Check termination criteria
    terminate_cond = terminate_check(x, time, stop, pos_tol, vel_tol, time_tol);
    if terminate_cond
        break
    end

end

fprintf('Simulation Finished....\n')


if OUTPUT_TO_VIDEO == 1
    close(v);
end

%% ************************* POST PROCESSING *************************
% Truncate xtraj and ttraj
for qn = 1:nquad
    xtraj{qn} = xtraj{qn}(1:iter*nstep,:);
    ttraj{qn} = ttraj{qn}(1:iter*nstep);
end

% Plot the saved position and velocity of each robot
if vis
    for qn = 1:nquad
        % Truncate saved variables
        QP{qn}.TruncateHist();
        % Plot position for each quad
        h_pos{qn} = figure('Name', ['Quad ' num2str(qn) ' : position']);
        plot_state(h_pos{qn}, QP{qn}.state_hist(1:3,:), QP{qn}.time_hist, 'pos', 'vic');
        plot_state(h_pos{qn}, QP{qn}.state_des_hist(1:3,:), QP{qn}.time_hist, 'pos', 'des');
        % Plot velocity for each quad
        h_vel{qn} = figure('Name', ['Quad ' num2str(qn) ' : velocity']);
        plot_state(h_vel{qn}, QP{qn}.state_hist(4:6,:), QP{qn}.time_hist, 'vel', 'vic');
        plot_state(h_vel{qn}, QP{qn}.state_des_hist(4:6,:), QP{qn}.time_hist, 'vel', 'des');
    end
end

figure(110)
plot3(desState(1,1:iter),desState(2,1:iter),desState(3,1:iter));
grid on
