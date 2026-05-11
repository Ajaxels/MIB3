function mib3_deploy
% the following wrapper is needed for mib

global running
running = 1;
mib3;
while running
    pause(0.05);
end
end