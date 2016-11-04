% This file provides example for SCOPF, implemented in Matpower (requires
% the latest version, version 6b1 at the time of writing this code)
clc;clear;
define_constants;
mpc = loadcase('case9_SCOPF');
% Decrease ratings
mpc.branch(:,RATE_A) = 0.7*mpc.branch(:,RATE_A);

%% Creates a contingency table for all lines and generators.
% Count number of N-1 contingencies
gens_on = mpc.gen(:,GEN_STATUS) == 1;
lines_on = mpc.branch(:,BR_STATUS) == 1;
nb_cont_gen = sum(gens_on);
nb_cont_line = sum(lines_on);
nb_cont = nb_cont_gen+nb_cont_line;

% Creates the contingency table with following columns:
% See p. 93 in MATPOWER manual (version 6b1)
%  label    proba   table       row     column      chg_type    newval
cont_tab = [...
    1       1e-3    CT_TGEN     1       GEN_STATUS  CT_REP      0; % Gen 1
    2       1e-3    CT_TGEN     2       GEN_STATUS  CT_REP      0; % Gen 2
    3       1e-3    CT_TGEN     3       GEN_STATUS  CT_REP      0; % Gen 3
    4       1e-3    CT_TBRCH    2       BR_STATUS   CT_REP      0; % branch 4 to 5
    5       1e-3    CT_TBRCH    3       BR_STATUS   CT_REP      0; % branch 5 to 6
    6       1e-3    CT_TBRCH    5       BR_STATUS   CT_REP      0; % branch 6 to 7
    7       1e-3    CT_TBRCH    6       BR_STATUS   CT_REP      0; % branch 7 to 8
    8       1e-3    CT_TBRCH    8       BR_STATUS   CT_REP      0; % branch 8 to 9
    9       1e-3    CT_TBRCH    9       BR_STATUS   CT_REP      0; % branch 9 to 4
    ];

% Texts to describe the contingencies
nc = size(cont_tab,1);
cont_descri = cell(nc,1);
for cc = 1:nc
    if cont_tab(cc,CT_TABLE) == CT_TGEN
        gen_nb = cont_tab(cc,CT_ROW);
        gen_bus = mpc.gen(gen_nb,GEN_BUS);
        cont_text = sprintf('Gen%d (bus%d)',gen_nb,gen_bus);
    elseif cont_tab(cc,CT_TABLE) == CT_TBRCH
        br_nb = cont_tab(cc,CT_ROW);
        br_fr = mpc.branch(br_nb,F_BUS);
        br_to = mpc.branch(br_nb,T_BUS);
        cont_text = sprintf('Line%d (bus%d-bus%d)',br_nb,br_fr,br_to);
    end
    cont_descri{cc} = cont_text;
end

%% Initialize with opf
mpopt_0 = mpoption('model','AC','pf.enforce_q_lims',1);
mpc0 = runopf(mpc,mpopt_0);

%% Contingency analyses
% we run a power flow for each post-contingency system
cont_ana_results = repmat(struct('Xa',[],'results',[]),nc,1);
for cc = 1:nc
    % we build the post-contingency system
    mpc_c = apply_changes(cc,mpc0,cont_tab);
    % run power flow
    results_c = runpf(mpc_c,mpopt_0);
    cont_ana_results(cc).Xa = assess_limits(results_c);
    cont_ana_results(cc).results = results_c;
end

% Print results of contingency analyses
fprintf(1,'====================================================\n');
fprintf(1,' CONTINGENCY ANALYSES\n');
fprintf(1,'====================================================\n');
for cc = 1:nc
    fprintf(' Contingency %d: %s \n',cc,cont_descri{cc});
    if cont_ana_results(cc).Xa.voltages.nb ~= 0
        fprintf('%s\n',cont_ana_results(cc).Xa.voltages.txt);
    else
        fprintf('No voltage violations\n');
    end
    if cont_ana_results(cc).Xa.line_flow.nb ~= 0
        fprintf('%s\n',cont_ana_results(cc).Xa.line_flow.txt);
    else
        fprintf('No line flow violations\n');
    end
    fprintf('--------------------------------------------------\n');
end
%% SCOPF setup
% Assumptions: the cost of generator
% re-dispatch is a linear function of the re-dispatch amount with slope
% equal to the marginal costs at the present production level
offer.PositiveActiveDeltaPrice = margcost(mpc0.gencost,mpc0.gen(:,PG));
offer.NegativeActiveDeltaPrice = offer.PositiveActiveDeltaPrice;
% Set also re-dispatch cost for changes in the base case
mpc0 = set_redispatch_cost(mpc0);
% Add the offers for activating reserves and the contingency table
mpc0.offer = offer;
mpc0.contingencies = cont_tab;
ramp0 = mpc0.gen(:,RAMP_10);

%% Preventive SCOPF
% No ramping after contingencies
mpc0.gen(:,RAMP_10) = 0;
% Solve preventive SCOPF for this set of contingencies
mpopt_0 = mpoption('model','AC','pf.enforce_q_lims',1);
[pscopf_results,pscopf_opt_value,pscopf_success] = sopf2_retry({'PDIPM','MIPS'},mpc0,mpopt_0);

%% Preventive SCOPF with only some line contingencies
mpc0.gen(:,RAMP_10) = 0;
mpc0.contingencies = cont_tab(4:8,:);
[pscopf_results,pscopf_opt_value,pscopf_success] = sopf2_retry({'PDIPM','MIPS'},mpc0,mpopt_0);

%% Preventive-Corrective SCOPF
mpc0.contingencies = cont_tab;
mpc0.gen(:,RAMP_10) = ramp0;
% Solve corrective SCOPF for this set of contingencies
mpopt_0 = mpoption('model','AC','pf.enforce_q_lims',1);
[results_PC,opt_value,success_PC] = sopf2_retry({'PDIPM','MIPS'},mpc0,mpopt_0);

%% Preventive-Corrective SCOPF with larger ramp rates
% Increase ramp rate
mpc0.gen(:,RAMP_10) = mpc0.gen(:,RAMP_10)*1.8;
% Solve corrective SCOPF for this set of contingencies
mpopt_0 = mpoption('model','AC','pf.enforce_q_lims',1);
[results_PC,opt_value,success_PC] = sopf2_retry({'PDIPM','MIPS'},mpc0,mpopt_0);

%% Corrective SCOPF with only some line contingencies
mpc0.contingencies = cont_tab(4:8,:);
mpc0.gen(:,RAMP_10) = ramp0;
[results_PC,opt_value,success_PC] = sopf2_retry({'PDIPM','MIPS'},mpc0,mpopt_0);