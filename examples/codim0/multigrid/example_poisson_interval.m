%% test geometric multigrid method to solve -\Delta u  = f on an interval, Dirichlet B.C.s
epsilon = 0;
q = 6; k = 6;
uexactfn = @(x) x.^q + sin(k*pi*x) + cos(k*pi*x);
rhsfn = @(x) q*(q-1)*x.^(q-2) - k^2*pi^2*(uexactfn(x)-x.^q) - epsilon*uexactfn(x);
g_Dirichlet = @(x) uexactfn(x);

x0 = -2;
x1 = 2;

%%
% 2D example on a circle
% Construct a grid in the embedding space

%dx = 0.025;
dx = 0.003125/2; % grid size
dx_coarsest = 0.05;   % coarsest grid size
x1d_coarsest = (x0:dx_coarsest:x1)';

dim = 1;  % dimension
p = 3;    % interpolation order
order = 2;  % Laplacian order: bw will need to increase if changed

bw = 1.0002*sqrt((dim-1)*((p+1)/2)^2 + ((order/2+(p+1)/2)^2));
%bw = 0;

n1 = 3;
n2 = 3;

p_f2c = 1;
p_c2f = 1;

w = 3/4;

a = -1.23989;
%a = -1;
b = 1;
cpf = @(x) cpIntervalInterior(x, [a,b]);
cpfS = @(x) cpInterval(x, [a,b]);

disp('building grids covering the domain... ')
[a_band, a_xcp, a_distg, a_bdyg, a_dx, a_x1d, a_xg] = ...
    build_mg_grid_1d(x1d_coarsest, dx_coarsest, dx, bw, cpf);

disp('building grids surrounding the surface... ')
[a_band_S, a_xcp_S, a_distg_S, ~, ~, a_xg_S] = ...
    build_mg_grid_1d(x1d_coarsest, dx_coarsest, dx, bw, cpfS);

n_level = length(a_band);

disp('building Laplacian matrices ... ')
L = cell(n_level,1);
for i = 1:1:n_level
   L{i} = laplacian_1d_matrix(a_x1d{i}, a_band{i}, order);
end

disp('building transform matrices to do restriction and prolongation later ... ')
[TMf2c, TMc2f] = helper_set_TM_1d(a_x1d, a_xg, a_band, a_bdyg, p_f2c, p_c2f);

disp('build the matrices that evaluate v at cps of boundary function on the surface')
Ecp_Omega_S = cell(n_level,1);
for i = 1:1:n_level
    Ecp_Omega_S{i} = interp1_matrix(a_x1d{i},a_xcp_S{i},p,a_band{i});
end
 
disp('build the matrices that evaluate v at cp(bdy) on course grid using values on fine grid')
Ecp_f2c_Omega = cell(n_level-1,1);
for i = 1:1:n_level-1
    Ecp_f2c_Omega{i} = interp1_matrix(a_x1d{i},a_xcp{i+1}(a_bdyg{i+1}),p_f2c,a_band{i});
end

disp('build the matrices that evaluate cp for course grid of S using values on fine grid of S')
Ecp_f2c_S = cell(n_level-1,1);
for i = 1:1:n_level-1
    Ecp_f2c_S{i} = interp1_matrix(a_x1d{i},a_xcp_S{i+1},p_f2c,a_band_S{i});
end

disp('build the matrices that evaluate boundary function at cp(bdy) for course grid of $\Omega$ using values on fine grid of S')
Ecp_f2c_Omega_S = cell(n_level-1,1);
for i = 1:1:n_level-1
    Ecp_f2c_Omega_S{i} = interp1_matrix(a_x1d{i},a_xcp{i+1}(a_bdyg{i+1}),p_f2c,a_band_S{i});
end

disp('setting up rhs and allocate spaces for solns')
F = cell(n_level,1);
V = cell(n_level,1);
FonS = cell(n_level,1);
for i = 1:1:n_level
    F{i} = rhsfn(a_xg{i}');
    F{i}(a_bdyg{i}) = g_Dirichlet(a_xcp{i}(a_bdyg{i}));
    V{i} = zeros(size(F{i}));
    FonS{i} = g_Dirichlet(a_xcp_S{i}');
end

disp('buidling matrices to deal with boundary conditions ... ')
E_out_out = cell(n_level,1);
E_out_in = cell(n_level,1); 
a_Ebar = cell(n_level,1);
a_Edouble = cell(n_level,1);
a_Etriple = cell(n_level,1);
for i = 1:1:n_level
    x1d = a_x1d{i}; band = a_band{i};
    I = speye(size(L{i}));
    bdy = a_bdyg{i};
    cpx_bar = 2*a_xcp{i}(bdy) - a_xg{i}(bdy);
    Ebar = interp1_matrix(x1d,cpx_bar,p,band);
    cpx_double = 2*cpx_bar - a_xcp{i}(bdy); 
    Edouble = interp1_matrix(x1d,cpx_double,p,band);
    cpx_triple = 2*cpx_double - cpx_bar;
    Etriple = interp1_matrix(x1d,cpx_triple,p,band);
    %L_bdy = (I(bdy,:) + Ebar)/2;
    L_bdy = (I(bdy,:) + 3*Ebar - Edouble) / 3;
    %L_bdy = (I(bdy,:) + 6*Ebar - 4*Edouble + Etriple) / 4;
    E_out_out{i} = L_bdy(:,bdy);
    E_out_in{i} = L_bdy(:,~bdy);
    L{i}(bdy,:) = L_bdy; 
    a_Ebar{i} = Ebar;
    a_Edouble{i} = Edouble;
    a_Etriple{i} = Etriple;
end 

disp('pre set-up done, start to solve ...')
error_inf_matlab = zeros(n_level-1,1);
res_matlab = zeros(n_level,1);
u_matlab = cell(n_level-1,1);
uexact = cell(n_level-1,1);
for i = 1:1:n_level-1
    tic;
    
    unew = L{i} \ F{i};
        
    t_matlab = toc
    
    uexact{i} = uexactfn(a_xg{i}');
    error = unew - uexact{i};

    error_inf_matlab(i) = max(abs( error(~a_bdyg{i}) )) / norm(uexact{i}(~a_bdyg{i}),inf);
    
    residual = F{i} - L{i}*unew;
    res_matlab(i) = norm(residual(~a_bdyg{i}),inf) / norm(F{i}(~a_bdyg{i}));
    
    u_matlab{i} = unew;

end
matlab_order = log(error_inf_matlab(2:end)./error_inf_matlab(1:end-1))/log(2);

error_inf_matlab = error_inf_matlab(end:-1:1);
matlab_order = matlab_order(end:-1:1);

MAX = 10;
err_inf = zeros(n_level-1,MAX);
res = zeros(n_level-1, MAX);
u_multigrid = cell(n_level-1,1);
for start = 1:1:n_level-1
    V{start} = zeros(size(F{start}));
    %V{start} = ones(size(F{start}));
    %V{start} = rand(size(F{start})) - 0.5;
    for i = start+1:1:n_level
        V{i} = zeros(size(F{i}));
    end
%     [umg, err_inf(start,:), res(start,:)] = ...
%         gmg(L, E_out_out, E_out_in, V, F, TMf2c, TMc2f, a_band, a_bdyg, n1, n2, start, w, uexact, MAX);
    [umg, err_inf(start,:), res(start,:)] = ...
        gmg_test(L, a_Ebar, a_Edouble, a_Etriple, E_out_out, E_out_in, Ecp_Omega_S, Ecp_f2c_Omega, Ecp_f2c_S, Ecp_f2c_Omega_S, V, F, FonS, TMf2c, TMc2f, a_band, a_bdyg, n1, n2, start, w, uexact, MAX);
    u_multigrid{start} = umg;
end

err_inf = err_inf(end:-1:1,:);
res = res(end:-1:1,:);

figure(1)
% rep_res_matlab = repmat(res_matlab, 1, 2);
% xx = [0 7];
% semilogy(xx,rep_res_matlab(1,:),'b',xx,rep_res_matlab(2,:),'r',xx,rep_res_matlab(3,:),'c', ...
%          xx,rep_res_matlab(4,:),'k',xx,rep_res_matlab(5,:),'g',xx,rep_res_matlab(6,:),'m', ...
%          xx,rep_res_matlab(7,:),'--',xx,rep_res_matlab(8,:),'r--');
% hold on

n = 1:MAX;
n = n - 1;
if n_level == 8
    semilogy(n,res(1,:),'o--',n,res(2,:),'r*--',n,res(3,:),'g+--', ...
             n,res(4,:),'k-s',n,res(5,:),'c^-',n,res(6,:),'m-d', ...
             n,res(7,:),'b.-');
    legend('N=10','N=20','N=40','N=80','N=160','N=320','N=640')
elseif n_level == 6
    semilogy(n,res(1,:),'o--',n,res(2,:),'r*--',n,res(3,:),'g+--', ...
             n,res(4,:),'k-s',n,res(5,:),'c^-');
    legend('N=10','N=20','N=40','N=80','N=160')
elseif n_level == 4
    semilogy(n,res(1,:),'o--',n,res(2,:),'r*--',n,res(3,:),'g+--');
    legend('N=10','N=20','N=40')    
end
% semilogy(n,res(1,:),'.-',n,res(2,:),'r*-');
% legend('N=20','N=10')
fs = 12;
set(gca,'Fontsize',fs)
title('\fontsize{15} relative residuals in the \infty-norm')
xlabel('\fontsize{15} number of v-cycles')
ylabel('\fontsize{15} ||f^h-A^hu^h||_{\infty}/||f^h||_{\infty}')
%title('\fontsize{15} residual |Eplot*(f-A*u)|')
%xlabel('\fontsize{15} number of v-cycles')
%ylabel('\fontsize{15} |residual|_{\infty}')
%title(['sin(\theta) with p=', num2str(p), ',  res = E*(f-L*v)'])
%title(['sin(\theta)+sin(',num2str(m),'\theta) with p=', num2str(p), ',  res = E*(f-L*v)'])

% plot error of matlab and error of different number of vcycles
figure(2)

n = 1:MAX;
n = n - 1;
if n_level == 8
    semilogy(n,err_inf(1,:),'o--',n,err_inf(2,:),'r*--',n,err_inf(3,:),'g+--', ...
         n,err_inf(4,:),'k-s',n,err_inf(5,:),'c^-',n,err_inf(6,:),'m-d', ...
            n,err_inf(7,:),'bx-');
    legend('N=10','N=20','N=40','N=80','N=160','N=320','N=640')
elseif n_level == 6
    semilogy(n,err_inf(1,:),'o--',n,err_inf(2,:),'r*--',n,err_inf(3,:),'g+--', ...
         n,err_inf(4,:),'k-s',n,err_inf(5,:),'c^-');
    legend('N=10','N=20','N=40','N=80','N=160')
elseif n_level == 4
    semilogy(n,err_inf(1,:),'o--',n,err_inf(2,:),'r*--',n,err_inf(3,:),'g+--');
    legend('N=10','N=20','N=40')
end
hold on
%err_inf_matlab = cell2mat(error_inf_matlab);
rep_err_inf_matlab = repmat(error_inf_matlab,1,2);
xx = [0 MAX];
if n_level == 8
    semilogy(xx,rep_err_inf_matlab(1,:),'b--',xx,rep_err_inf_matlab(2,:),'r--',xx,rep_err_inf_matlab(3,:),'g', ...
         xx,rep_err_inf_matlab(4,:),'k',xx,rep_err_inf_matlab(5,:),'c', xx,rep_err_inf_matlab(6,:),'m-', ...
            xx,rep_err_inf_matlab(7,:),'b-');
elseif n_level == 6
    semilogy(xx,rep_err_inf_matlab(1,:),'b--',xx,rep_err_inf_matlab(2,:),'r--',xx,rep_err_inf_matlab(3,:),'g', ...
         xx,rep_err_inf_matlab(4,:),'k',xx,rep_err_inf_matlab(5,:),'c');
elseif n_level == 4
     semilogy(xx,rep_err_inf_matlab(1,:),'b--',xx,rep_err_inf_matlab(2,:),'r--',xx,rep_err_inf_matlab(3,:),'g');
end

% semilogy(n,err_inf(1,:),'.-',n,err_inf(2,:),'r*-');
% legend('N=20','N=10')

fs = 12;
set(gca,'Fontsize',fs)
xlabel('\fontsize{15} number of v-cycles')
ylabel('\fontsize{15} ||u^h-u||_{\infty}/||u||_{\infty}')
%xlim([0,10])