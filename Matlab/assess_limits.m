function violations = assess_limits(mpc,varargin)
% This function takes a mpc case and prints all relevant quantities with
% their limits.
define_constants;

%% Checking the options, if any
input_checker = inputParser;

% verbose
default_verbose = 0;
check_verbose = @(x)(isnumeric(x) && isscalar(x));
addParameter(input_checker,'verbose',default_verbose,check_verbose);

% Line limits on S, P or I
default_flow_lim = 'P'; 
check_flow_lim = @(x)(ischar(x) && (strcmp(x,'S') || strcmp(x,'P') || strcmp(x,'I')));
addParameter(input_checker,'flow_lim',default_flow_lim,check_flow_lim);

% ST or LT limits
default_flow_lim_term = 'LT'; % By default, long-term rating
check_flow_lim_term = @(x)(ischar(x) && (strcmp(x,'LT') || strcmp(x,'ST') || strcmp(x,'EM')));
addParameter(input_checker,'flow_lim_term',default_flow_lim_term,check_flow_lim_term);

% Tolerance to check limits
default_tolerance = 1e-6; 
check_tolerance = @(x)(isnumeric(x) && isscalar(x));
addParameter(input_checker,'tol',default_tolerance,check_tolerance);

input_checker.KeepUnmatched = true;
parse(input_checker,varargin{:});

options = input_checker.Results;

% Replace type of line limits if already included in mpc
if isfield(mpc,'opf') && isfield(mpc.opf,'flow_lim')
    options.flow_lim = mpc.opf.flow_lim;
end


%% Voltages
voltage_violations.txt = '';
voltage_violations.nb = 0;
nb = size(mpc.bus,1);
if options.verbose
    fprintf(1,'=============================================\n');
    fprintf(1,'  BUS VOLTAGES\n');
    fprintf(1,'=============================================\n');
    fprintf(1,'Bus nb     VMIN       VM       VMAX     VIOL\n');
    fprintf(1,'------     ----     ------     ----     ----\n');
end
for i = 1:nb
    % Check if the voltage constraints at this bus are violated
    violation_min = mpc.bus(i,VMIN) > mpc.bus(i,VM)+options.tol;
    violation_max = mpc.bus(i,VM)-options.tol > mpc.bus(i,VMAX);
    violation = violation_min | violation_max;
    if violation
        viol_txt = 'X';
        voltage_violations.nb = voltage_violations.nb+1;
    else
        viol_txt = '';
    end
    if options.verbose
        fprintf(1,'%6d     %4.2f     %6.4f     %4.2f      %s\n',...
        mpc.bus(i,BUS_I),mpc.bus(i,VMIN),mpc.bus(i,VM),mpc.bus(i,VMAX),viol_txt);
    end
    if violation_min
        voltage_violations.txt = sprintf('%sLow voltage limit violated at bus %d: VM = %.4f < VMIN = %.2f\n',...
            voltage_violations.txt,mpc.bus(i,BUS_I),mpc.bus(i,VM),mpc.bus(i,VMIN));
    elseif violation_max
        voltage_violations.txt = sprintf('%sUpper voltage limit violated at bus %d: VM = %.4f > VMAX = %.2f\n',...
            voltage_violations.txt,mpc.bus(i,BUS_I),mpc.bus(i,VM),mpc.bus(i,VMAX));
    end
end
if options.verbose
    fprintf(1,'=============================================\n\n');
end
%% Generators
gen_p_violations.txt = '';
gen_p_violations.nb = 0;
ng = size(mpc.gen,1);
if options.verbose
    fprintf(1,'==========================================================================\n');
    fprintf(1,'  GENERATOR - ACTIVE POWER LIMITS \n');
    fprintf(1,'==========================================================================\n');
    fprintf(1,'Gen nb     Bus_nb     STATUS       PMIN         PG          PMAX      VIOL\n');
    fprintf(1,'------     ------     ------     -------     --------     -------     ----\n');
end
% check the bus types to determine the new slack bus used in the PF if the
% original slack bus was not defined (because the generators at that bus 
% were off)
[slack_bus,~] = bustypes(mpc.bus,mpc.gen);
for i = 1:ng
    % Check if active power limits are violated for the non-slack generator
    gen_is_slack = mpc.bus(mpc.gen(i,GEN_BUS),BUS_TYPE) == slack_bus;
    violation_min = ~gen_is_slack & mpc.gen(i,GEN_STATUS) & (mpc.gen(i,PMIN) > mpc.gen(i,PG));
    violation_max = ~gen_is_slack & mpc.gen(i,GEN_STATUS) & (mpc.gen(i,PG) > mpc.gen(i,PMAX));
    violation = violation_min | violation_max;
    if violation
        viol_txt = 'X';
        gen_p_violations.nb = gen_p_violations.nb+1;
    else
        viol_txt = '';
    end
    if mpc.gen(i,GEN_STATUS) 
        status_txt = 'ON';
    else
        status_txt = 'OFF';
    end
    if options.verbose
        fprintf(1,'%6d     %6d     %6s     %7.2f     %7.2f     %7.2f     %s\n',...
            i,mpc.gen(i,GEN_BUS),status_txt,mpc.gen(i,PMIN),mpc.gen(i,PG),...
            mpc.gen(i,PMAX),viol_txt);
    end
    if violation_min
        gen_p_violations.txt = sprintf('%sLow active power limit violated at gen %d at bus %d: PG = %.2f < PMIN = %.2f\n',...
            gen_p_violations.txt,i,mpc.gen(i,GEN_BUS),mpc.gen(i,PG),mpc.gen(i,PMIN));
    elseif violation_max
        gen_p_violations.txt = sprintf('%sUpper active power limit violated at gen %d at bus %d: PG = %.2f > PMAX = %.2f\n',...
            gen_p_violations.txt,i,mpc.gen(i,GEN_BUS),mpc.gen(i,PG),mpc.gen(i,PMAX));
    end
end
if options.verbose
    fprintf(1,'==========================================================================\n\n');
end

gen_q_violations.txt = '';
gen_q_violations.nb = 0;
if options.verbose
    fprintf(1,'==========================================================================\n');
    fprintf(1,'  GENERATOR - REACTIVE POWER LIMITS \n');
    fprintf(1,'==========================================================================\n');
    fprintf(1,'Gen nb     Bus_nb     STATUS       QMIN         QG          QMAX      VIOL\n');
    fprintf(1,'------     ------     ------     -------     --------     -------     ----\n');
end
for i = 1:ng
    % Check if active power limits are violated
    violation_min = mpc.gen(i,GEN_STATUS)  & (mpc.gen(i,QMIN) > mpc.gen(i,QG));
    violation_max = mpc.gen(i,GEN_STATUS)  & (mpc.gen(i,QG) > mpc.gen(i,QMAX));
    violation = violation_min | violation_max;
    if violation
        viol_txt = 'X';
        gen_q_violations.nb = gen_q_violations.nb+1;
    else
        viol_txt = '';
    end
    if mpc.gen(i,GEN_STATUS) == 1
        status_txt = 'ON';
    else
        status_txt = 'OFF';
    end
    if options.verbose
        fprintf(1,'%6d     %6d     %6s     %7.2f     %7.2f     %7.2f     %s\n',...
            i,mpc.gen(i,GEN_BUS),status_txt,mpc.gen(i,QMIN),mpc.gen(i,QG),...
            mpc.gen(i,QMAX),viol_txt);
    end
    if violation_min
        gen_q_violations.txt = sprintf('%sLow reactive power limit violated at gen %d at bus %d: QG = %.2f < QMIN = %.2f\n',...
            gen_q_violations.txt,i,mpc.gen(i,GEN_BUS),mpc.gen(i,QG),mpc.gen(i,QMIN));
    elseif violation_max
        gen_q_violations.txt = sprintf('%sUpper reactive power limit violated at gen %d at bus %d: QG = %.2f > QMAX = %.2f\n',...
            gen_q_violations.txt,i,mpc.gen(i,GEN_BUS),mpc.gen(i,QG),mpc.gen(i,QMAX));
    end
end
if options.verbose
    fprintf(1,'==========================================================================\n\n');
end

%% Branches
line_flow_violations.txt = '';
line_flow_violations.nb = 0;
nb = size(mpc.branch,1);

switch options.flow_lim_term
    case 'LT'
        flow_lim_term_txt = 'Long-term';
        rating_idx = RATE_A;
    case 'ST'
        flow_lim_term_txt = 'Short-term';
        rating_idx = RATE_B;
    case 'EM'
        flow_lim_term_txt = 'Emergency';
        rating_idx = RATE_C;
end

if options.verbose
    fprintf(1,'================================================================================\n');
    fprintf(1,'  BRANCH FLOW %s LIMITS (on %s) \n',upper(flow_lim_term_txt),options.flow_lim);
    fprintf(1,'================================================================================\n');
    fprintf(1,'Line #    Bus Fr.    Bus To    STATUS    Flow Fr.    Flow To     LIMIT      VIOL\n');
    fprintf(1,'------    -------    ------    ------    --------    --------    -------    ----\n');
end
for i = 1:nb
    if strcmp(options.flow_lim,'P')
        flow_fr = mpc.branch(i,PF);
        flow_to = mpc.branch(i,PT);
    elseif strcmp(options.flow_lim,'S')
        flow_fr = sqrt(mpc.branch(i,PF).^2+mpc.branch(i,QF).^2);
        flow_to = sqrt(mpc.branch(i,PT).^2+mpc.branch(i,QT).^2);
    end
    violation_fr = mpc.branch(i,BR_STATUS) & (abs(flow_fr) > mpc.branch(i,rating_idx));
    violation_to = mpc.branch(i,BR_STATUS) & (abs(flow_to) > mpc.branch(i,rating_idx));
    violation = violation_fr | violation_to;
    if violation
        viol_txt = 'X';
        line_flow_violations.nb = line_flow_violations.nb+1;
    else
        viol_txt = '';
    end
    if mpc.branch(i,BR_STATUS) == 1
        status_txt = 'ON';
    else
        status_txt = 'OFF';
    end
    if options.verbose
        fprintf(1,'%6d    %7d    %6d    %6s    %8.2f    %8.2f    %7.2f    %s\n',...
            i,mpc.branch(i,F_BUS),mpc.branch(i,T_BUS),status_txt,...
            flow_fr,flow_to,mpc.branch(i,rating_idx),viol_txt);
    end
    if violation_fr
        line_flow_violations.txt = sprintf('%s%s "%s" flow limit violated on line %d (bus %d to %d): "from end" flow = %.2f > limit = %.2f\n',...
            line_flow_violations.txt,flow_lim_term_txt,options.flow_lim,i,mpc.branch(i,F_BUS),mpc.branch(i,T_BUS),...
            abs(flow_fr),mpc.branch(i,rating_idx));
    elseif violation_to
        line_flow_violations.txt = sprintf('%s%s "%s" flow limit violated on line %d (bus %d to %d): "to end" flow = %.2f > limit = %.2f\n',...
            line_flow_violations.txt,flow_lim_term_txt,options.flow_lim,i,mpc.branch(i,F_BUS),mpc.branch(i,T_BUS),...
            abs(flow_to),mpc.branch(i,rating_idx));
    end
end
if options.verbose
    fprintf(1,'================================================================================\n\n');
end

%% Gathering the violations
violations.voltages = voltage_violations;
violations.gen_p = gen_p_violations;
violations.gen_q = gen_q_violations;
violations.line_flow = line_flow_violations;
violations.success = mpc.success;
end