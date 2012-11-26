      subroutine advance(vel_old,vel_new,scal_old,scal_new,
     $                   I_R,press_old,press_new,
     $                   divu_old,divu_new,dsdt,beta_old,beta_new,
     $                   dx,dt,lo,hi,bc,delta_chi)

      implicit none

      include 'spec.h'

c     cell-centered, 2 ghost cells
      real*8    vel_old(0:nlevs-1,-2:nfine+1)
      real*8    vel_new(0:nlevs-1,-2:nfine+1)
      real*8   scal_new(0:nlevs-1,-2:nfine+1,nscal)
      real*8   scal_old(0:nlevs-1,-2:nfine+1,nscal)

c     cell-centered, 1 ghost cell
      real*8        I_R(0:nlevs-1,-1:nfine  ,0:Nspec)
      real*8   beta_old(0:nlevs-1,-1:nfine  ,nscal)
      real*8   beta_new(0:nlevs-1,-1:nfine  ,nscal)
      real*8   divu_old(0:nlevs-1,-1:nfine)
      real*8   divu_new(0:nlevs-1,-1:nfine)

c     cell-centered, no ghost cells
      real*8       dsdt(0:nlevs-1, 0:nfine-1)
      real*8  delta_chi(0:nlevs-1, 0:nfine-1)

c     nodal, 1 ghost cell
      real*8  press_old(0:nlevs-1,-1:nfine+1)
      real*8  press_new(0:nlevs-1,-1:nfine+1)

      integer lo(0:nlevs-1)
      integer hi(0:nlevs-1)
      integer bc(0:nlevs-1,2)
      real*8  dx(0:nlevs-1)
      real*8  dt(0:nlevs-1)

c     local variables

c     cell-centered, 1 ghost cell
      real*8       mu_old(0:nlevs-1,-1:nfine)
      real*8       mu_new(0:nlevs-1,-1:nfine)
      real*8     mu_dummy(0:nlevs-1,-1:nfine)
      real*8           gp(0:nlevs-1,-1:nfine)
      real*8         visc(0:nlevs-1,-1:nfine)
      real*8     I_R_divu(0:nlevs-1,-1:nfine,  0:Nspec)
      real*8     I_R_temp(0:nlevs-1,-1:nfine,  0:Nspec)
      real*8     diff_old(0:nlevs-1,-1:nfine,  nscal)
      real*8     diff_new(0:nlevs-1,-1:nfine,  nscal)
      real*8     diff_hat(0:nlevs-1,-1:nfine,  nscal)
      real*8     diff_tmp(0:nlevs-1,-1:nfine,  nscal)
      real*8       tforce(0:nlevs-1,-1:nfine,  nscal)
      real*8 diffdiff_old(0:nlevs-1,-1:nfine)
      real*8 diffdiff_new(0:nlevs-1,-1:nfine)
      real*8  divu_extrap(0:nlevs-1,-1:nfine)
      real*8     divu_eff(0:nlevs-1,-1:nfine)

c     cell-centered, no ghost cells
      real*8      rhohalf(0:nlevs-1, 0:nfine-1)
      real*8        alpha(0:nlevs-1, 0:nfine-1)
      real*8      vel_Rhs(0:nlevs-1, 0:nfine-1)
      real*8         aofs(0:nlevs-1, 0:nfine-1,nscal)
      real*8 spec_flux_lo(0:nlevs-1, 0:nfine-1,Nspec)
      real*8 spec_flux_hi(0:nlevs-1, 0:nfine-1,Nspec)
      real*8    const_src(0:nlevs-1, 0:nfine-1,nscal)
      real*8  lin_src_old(0:nlevs-1, 0:nfine-1,nscal)
      real*8  lin_src_new(0:nlevs-1, 0:nfine-1,nscal)
      real*8          Rhs(0:nlevs-1, 0:nfine-1,nscal)
      real*8         dRhs(0:nlevs-1, 0:nfine-1,0:Nspec)

c     nodal, no ghost cells
      real*8       macvel(0:nlevs-1, 0:nfine  )
      real*8      veledge(0:nlevs-1, 0:nfine  )

c     stuff for iterative dpdt fix
      real*8 cp, dummy, gamma_inv, mwmix, Runiv

      real*8 Y(Nspec),WDOTK(Nspec),C(Nspec),RWRK
      real*8 cpmix,rhocp,vel_theta,be_cn_theta
      
      integer i,is,misdc,n,rho_flag,IWRK

      print *,'advance: at start of time step'

c     
c*****************************************************************
c     Level 0 Advance
c*****************************************************************
c     
      do i=lo(0)-1,hi(0)+1
         gp(0,i) = (press_old(0,i+1) - press_old(0,i)) / dx(0)
      enddo

      print *,'... predict edge velocities'
      call pre_mac_predict(vel_old(0,:),scal_old(0,:,:),gp(0,:),
     $                     macvel(0,:),dx(0),dt(0),lo(0),hi(0),bc(0,:))

      call compute_pthermo(scal_old(0,:,:),lo(0),hi(0),bc(0,:))

      do i=lo(0),hi(0)
         divu_extrap(0,i) = divu_old(0,i) + 0.5d0*dt(0)*dsdt(0,i)
         divu_eff(0,i) = divu_extrap(0,i)
      end do

      if (fancy_dpdt_fix .eq. 1) then

         do i=lo(0),hi(0)
            do n = 1,Nspec
               is = FirstSpec + n - 1
               Y(n) = scal_old(0,i,is)/scal_old(0,i,Density)
            enddo
c     compute 1/gamma
            call CKMMWY(Y,IWRK,RWRK,mwmix)
            call CKRP(IWRK,RWRK,Runiv,dummy,dummy) 
            call CKCPBS(scal_old(0,i,Temp),Y,IWRK,RWRK,cp)

            gamma_inv = (cp - Runiv/mwmix)/cp

c     delta_chi = delta_chi + (1/gamma)*(ptherm-p0)/(dt*ptherm)
            delta_chi(0,i) = delta_chi(0,i) 
     $           + gamma_inv*(scal_old(0,i,RhoRT)-pcgs)/(dt(0)*pcgs)

            divu_eff(0,i) = divu_eff(0,i) + delta_chi(0,i)
         end do

      else

         call add_dpdt(scal_old(0,:,:),scal_old(0,:,RhoRT),divu_eff(0,:),
     $                 macvel(0,:),dx(0),dt(0),
     $                 lo(0),hi(0),bc(0,:))

      end if

      call macproj(macvel(0,:),scal_old(0,:,Density),divu_eff(0,:),dx,
     &             lo(0),hi(0),bc(0,:))

c     compute diffusivities at time n (old time)
c     this computes rho D_m     (for species)
c                   lambda / cp (for enthalpy)
c                   lambda      (for temperature)
      call calc_diffusivities(scal_old(0,:,:),beta_old(0,:,:),
     &                        mu_old(0,:),lo(0),hi(0))

      diffdiff_old(0,:) = 0.d0
      diffdiff_new(0,:) = 0.d0

      if (use_strang) then

C----------------------------------------------------------------
c     Strang advance
C----------------------------------------------------------------

         be_cn_theta = 0.5d0

         print *,'... react for dt/2;  set I_R'
         do n = 1,nscal
            do i=lo(0),hi(0)
               const_src(0,i,n) = 0.d0
               lin_src_old(0,i,n) = 0.d0
               lin_src_new(0,i,n) = 0.d0
            enddo
         enddo
         call strang_chem(scal_old(0,:,:),scal_new(0,:,:),
     $                    const_src(0,:,:),lin_src_old(0,:,:),
     $                    lin_src_new(0,:,:),
     $                    I_R(0,:,:),dt(0)/2.d0,lo(0),hi(0),bc(0,:))
         
         do n = FirstSpec,LastSpec
            scal_old(0,:,n) = scal_new(0,:,n)
         enddo

c     we only care about updated species out of strang_chem
c     rho and rhoh remain constant
c     call the EOS to get consistent temperature
         call rhoh_to_temp(scal_old(0,:,:),lo(0),hi(0))

         print *,'... creating the diffusive terms with old data'
c     compute rho^(1) D_m^(1)     (for species)
c             lambda^(1) / cp^(1) (for enthalpy)
c             lambda^(1)          (for temperature) 
         call calc_diffusivities(scal_old(0,:,:),beta_old(0,:,:),
     &                           mu_dummy(0,:),lo(0),hi(0))

c     compute del dot lambda grad T + rho D grad h dot grad Y
c     the rho D grad Y term is now computed conservatively
         call get_temp_visc_terms(scal_old(0,:,:),beta_old(0,:,:),
     &                            diff_old(0,:,Temp),dx(0),lo(0),hi(0))
c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
         call get_spec_visc_terms(scal_old(0,:,:),beta_old(0,:,:),
     &                            diff_old(0,:,FirstSpec:),
     &                            spec_flux_lo(0,:,:),
     &                            spec_flux_hi(0,:,:),
     &                            dx(0),lo(0),hi(0))
c     compute del dot lambda/cp grad h (no differential diffusion)
         call get_rhoh_visc_terms(scal_old(0,:,:),beta_old(0,:,:),
     &                            diff_old(0,:,RhoH),dx(0),lo(0),hi(0))

c     calculate differential diffusion
         if (LeEQ1 .eq. 0) then
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
            call get_diffdiff_terms(scal_old(0,:,:),scal_old(0,:,:),
     $                              spec_flux_lo(0,:,:),
     $                              spec_flux_hi(0,:,:),beta_old(0,:,:),
     $                              diffdiff_old(0,:),dx(0),lo(0),hi(0))
         end if
            
         print *,'... computing aofs with D(old)'

         do i=lo(0),hi(0)
            do n = 1,Nspec
               is = FirstSpec + n - 1
               tforce(0,i,is) = diff_old(0,i,is)
            enddo
            tforce(0,i,RhoH) = diff_old(0,i,RhoH) + diffdiff_old(0,i)
         enddo
       
         call scal_aofs(scal_old(0,:,:),macvel(0,:),aofs(0,:,:),
     $                  divu_eff(0,:),tforce(0,:,:),dx(0),dt(0),
     $                  lo(0),hi(0),bc(0,:))

         print *,'... update rho'
         call update_rho(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                   dt(0),lo(0),hi(0),bc(0,:))

         do i=lo(0),hi(0)
            do n = 1,Nspec
               Y(n) = scal_old(0,i,FirstSpec+n-1) / scal_old(0,i,Density)
            enddo
            call CKCPBS(scal_old(0,i,Temp),Y,IWRK,RWRK,cpmix)
            rhocp = cpmix * 
     &           (scal_old(0,i,Density) + scal_new(0,i,Density)) / 2.d0
            tforce(0,i,Temp) = diff_old(0,i,Temp)/rhocp
         end do

c*****************************************************************
c     Either do c-n solve for new T prior to computing new 
c     coeffs, or simply start by copying from previous time step
         if (predict_temp_for_coeffs .eq. 1) then
            print *,'... predict temp with old coeffs'
            rho_flag = 1
            call update_temp(scal_old(0,:,:),scal_new(0,:,:),
     $                       aofs(0,:,:),alpha(0,:),
     $                       beta_old(0,:,:),beta_old(0,:,:),
     $                       Rhs(0,:,Temp),dx(0),dt(0),be_cn_theta,
     $                       lo(0),hi(0),bc(0,:))
c     just uses RHS and overwrites snew
c     does not fill ghost cells
            call cn_solve(scal_new(0,:,:),alpha(0,:),beta_old(0,:,:),
     $                    Rhs(0,:,Temp),dx(0),dt(0),Temp,be_cn_theta,
     $                    rho_flag,.false.,lo(0),hi(0),bc(0,:))

            print *,'... compute new coeffs'
c     compute rho^(2) D_m^(2),* (for species)
c     lambda/cp (for enthalpy) won't be used
c     lambda^(1) (for temperature) won't be used
            call calc_diffusivities(scal_new(0,:,:),beta_new(0,:,:),
     &                              mu_dummy(0,:),lo(0),hi(0))
         else
            print *,'... set new coeffs to old values for predictor'
            do n=1,nscal
               do i=lo(0)-1,hi(0)+1
                  scal_new(0,i,Temp) = scal_old(0,i,Temp)
                  beta_new(0,i,n) = beta_old(0,i,n)
               enddo
            enddo
         endif

         print *,'... do predictor for species'
         do i=lo(0),hi(0)
            dRhs(0,i,0) = 0.0d0
            do n=1,Nspec
               dRhs(0,i,n) = 0.d0
            enddo
         enddo
         call update_spec(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,0:,1:),Rhs(0,0:,FirstSpec:),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))

         rho_flag = 2
         do n=1,Nspec
            is = FirstSpec + n - 1
            call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                    Rhs(0,:,is),dx(0),dt(0),is,be_cn_theta,
     $                    rho_flag,.false.,lo(0),hi(0),bc(0,:))
         enddo
      
         if (LeEQ1 .eq. 0) then

c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
            call get_spec_visc_terms(scal_new(0,:,:),beta_new(0,:,:),
     &                               diff_tmp(0,:,FirstSpec:),
     &                               spec_flux_lo(0,:,:),
     &                               spec_flux_hi(0,:,:),
     &                               dx(0),lo(0),hi(0))

c     update species with conservative diffusion fluxes
            do i=lo(0),hi(0)
               do n=1,Nspec
                  is = FirstSpec + n - 1
                  scal_new(0,i,is) = scal_old(0,i,is) + 
     $                 dt(0)*(aofs(0,i,is)
     $                 + 0.5d0*diff_old(0,i,is) + 0.5d0*diff_tmp(0,i,is))
               end do
            end do
            call set_bc_s(scal_new(0,:,:),lo(0),hi(0),bc(0,:))
            
         end if

c     this computes rho D_m                 (for species) won't be used
c                   lambda^(2),* / cp^(2),* (for enthalpy)
c                   lambda^(2),*            (for temperature) 
         call calc_diffusivities(scal_new(0,:,:),beta_new(0,:,:),
     &                           mu_dummy(0,:),lo(0),hi(0))

         if (LeEQ1 .eq. 0) then

c     calculate differential diffusion
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
            call get_diffdiff_terms(scal_new(0,:,:),scal_new(0,:,:),
     $                              spec_flux_lo(0,:,:),
     $                              spec_flux_hi(0,:,:),beta_new(0,:,:),
     $                              diffdiff_new(0,:),dx(0),lo(0),hi(0))
         
            do i=lo(0),hi(0)
               dRhs(0,i,0) = dRhs(0,i,0)
     $              + 0.5d0*dt(0)*(diffdiff_old(0,i) + diffdiff_new(0,i))
            end do
            
         end if

         print *,'... do predictor for rhoh (MISDC terms=0)'
         call update_rhoh(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,:,0),Rhs(0,:,RhoH),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))
         rho_flag = 2
         call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                 Rhs(0,:,RhoH),dx(0),dt(0),RhoH,be_cn_theta,
     $                 rho_flag,.false.,lo(0),hi(0),bc(0,:))

         call rhoh_to_temp(scal_new(0,:,:),lo(0),hi(0))

C----------------------------------------------------------------
C     Corrector

         print *,'... compute new coeffs'
c     this computes rho^(2) D_m^(2)     (for species)
c                   lambda^(2) / cp^(2) (for enthalpy)
c                   lambda^(2)          (for temperature) 
         call calc_diffusivities(scal_new(0,:,:),beta_new(0,:,:),
     &                           mu_dummy(0,:),lo(0),hi(0))

         do i=lo(0),hi(0)
            dRhs(0,i,0) = 0.0d0
            do n=1,Nspec
               dRhs(0,i,n) = 0.d0
            enddo
         enddo
         call update_spec(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,0:,1:),Rhs(0,0:,FirstSpec:),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))

         rho_flag = 2
         do n=1,Nspec
            is = FirstSpec + n - 1
            call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                    Rhs(0,:,is),dx(0),dt(0),is,be_cn_theta,
     $                    rho_flag,.false.,lo(0),hi(0),bc(0,:))
         enddo

         if (LeEQ1 .eq. 0) then

c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
            call get_spec_visc_terms(scal_new(0,:,:),beta_new(0,:,:),
     &                               diff_tmp(0,:,FirstSpec:),
     &                               spec_flux_lo(0,:,:),
     &                               spec_flux_hi(0,:,:),
     &                               dx(0),lo(0),hi(0))

c     update species with conservative diffusion fluxes
            do i=lo(0),hi(0)
               do n=1,Nspec
                  is = FirstSpec + n - 1
                  scal_new(0,i,is) = scal_old(0,i,is) + 
     $                 dt(0)*(aofs(0,i,is)
     $                 + 0.5d0*diff_old(0,i,is) + 0.5d0*diff_tmp(0,i,is))
               end do
            end do
            call set_bc_s(scal_new(0,:,:),lo(0),hi(0),bc(0,:))

c     calculate differential diffusion
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
            call get_diffdiff_terms(scal_new(0,:,:),scal_new(0,:,:),
     $                              spec_flux_lo(0,:,:),
     $                              spec_flux_hi(0,:,:),beta_new(0,:,:),
     $                              diffdiff_new(0,:),dx(0),lo(0),hi(0))

            do i=lo(0),hi(0)
               dRhs(0,i,0) = dRhs(0,i,0)
     $              + 0.5d0*dt(0)*(diffdiff_old(0,i) + diffdiff_new(0,i))
            end do
            
         end if
         
         print *,'... do predictor for rhoh (MISDC terms=0)'
         call update_rhoh(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,:,0),Rhs(0,:,RhoH),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))
         rho_flag = 2
         call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                 Rhs(0,:,RhoH),dx(0),dt(0),RhoH,be_cn_theta,
     $                 rho_flag,.false.,lo(0),hi(0),bc(0,:))

         call rhoh_to_temp(scal_new(0,:,:),lo(0),hi(0))

         do i=lo(0),hi(0)
            do n = FirstSpec,LastSpec
               scal_old(0,i,n) = scal_new(0,i,n)
            enddo
            scal_old(0,i,Temp) = scal_new(0,i,Temp)
            scal_old(0,i,Density) = scal_new(0,i,Density)
         enddo
         call strang_chem(scal_old(0,:,:),scal_new(0,:,:),
     $                    const_src(0,:,:),lin_src_old(0,:,:),
     $                    lin_src_new(0,:,:),
     $                    I_R_temp(0,:,:),dt(0)/2.d0,
     $                    lo(0),hi(0),bc(0,:))

c     we only care about updated species out of strang_chem
c     rho and rhoh remain constant
c     call the EOS to get consistent temperature
         call rhoh_to_temp(scal_new(0,:,:),lo(0),hi(0))
         
         I_R(0,:,:) = I_R(0,:,:) + I_R_temp(0,:,:)
         I_R(0,:,:) = I_R(0,:,:) / 2.d0

      else

C----------------------------------------------------------------
c     SDC advance
C----------------------------------------------------------------

C----------------------------------------------------------------
c     Begin initial predictor
C----------------------------------------------------------------

c     diffusion solves in predictor are regular Crank-Nicolson
         be_cn_theta = 0.5d0

c     compute diffusion term at time n
         print *,'... computing D(U^n)'
c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
         call get_spec_visc_terms(scal_old(0,:,:),beta_old(0,:,:),
     &                            diff_old(0,:,FirstSpec:),
     &                            spec_flux_lo(0,:,:),spec_flux_hi(0,:,:),
     &                            dx(0),lo(0),hi(0))
c     compute del dot lambda/cp grad h (no differential diffusion)
         call get_rhoh_visc_terms(scal_old(0,:,:),beta_old(0,:,:),
     &                            diff_old(0,:,RhoH),dx(0),lo(0),hi(0))

c     calculate differential diffusion
         if (LeEQ1 .eq. 0) then
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
            call get_diffdiff_terms(scal_old(0,:,:),scal_old(0,:,:),
     $                              spec_flux_lo(0,:,:),
     $                              spec_flux_hi(0,:,:),beta_old(0,:,:),
     $                              diffdiff_old(0,:),dx(0),lo(0),hi(0))
         end if

c     If .true., use I_R in predictor is instantaneous value at t^n
c     If .false., use I_R^lagged = I_R^kmax from previous time step
         if (.false.) then
            do i=lo(0),hi(0)
               do n=1,Nspec
                  C(n) = scal_old(0,i,FirstSpec+n-1)*invmwt(n)
               end do
               call CKWC(scal_old(0,i,Temp),C,IWRK,RWRK,WDOTK)
               do n=1,Nspec
                  I_R(0,i,n) = WDOTK(n)*mwt(n)
               end do
            end do
         end if

c     compute advective forcing term
         print *,'... computing A forcing term = D^n + I_R^kmax'
         do i=lo(0),hi(0)
            do n = 1,Nspec
               is = FirstSpec + n - 1
               tforce(0,i,is) = diff_old(0,i,is) + I_R(0,i,n)
            enddo
            tforce(0,i,RhoH) = diff_old(0,i,RhoH) + diffdiff_old(0,i)
         enddo

c     compute advection term
         call scal_aofs(scal_old(0,:,:),macvel(0,:),aofs(0,:,:),
     $                  divu_eff(0,:),tforce(0,:,:),dx(0),dt(0),
     $                  lo(0),hi(0),bc(0,:))

c     update density
         print *,'... update rho'
         call update_rho(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                   dt(0),lo(0),hi(0),bc(0,:))

c     compute part of the RHS for the enthalpy and species
c     diffusion solves
         do i=lo(0),hi(0)
            dRhs(0,i,0) = 0.0d0
            do n=1,Nspec
               dRhs(0,i,n) = dt(0)*I_R(0,i,n)
            enddo
         enddo

c     compute RHS for species diffusion solve
         call update_spec(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,0:,1:),Rhs(0,0:,FirstSpec:),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))

C     update species with diffusion solve
         print *,'... do initial diffusion solve for species'
         rho_flag = 2
         do n=1,Nspec
            is = FirstSpec + n - 1
            call cn_solve(scal_new(0,:,:),alpha(0,:),beta_old(0,:,:),
     $                    Rhs(0,:,is),dx(0),dt(0),is,be_cn_theta,rho_flag,
     $                    .false.,lo(0),hi(0),bc(0,:))
         enddo

         if (LeEQ1 .eq. 1) then
            
c     simply extract D for RhoX
            do i=lo(0),hi(0)
               do n=1,Nspec
                  is = FirstSpec + n - 1
                  diff_hat(0,i,is) = 2.d0*((scal_new(0,i,is)-scal_old(0,i,is))/dt(0)
     $                 - aofs(0,i,is) - I_R(0,i,n) - 0.5d0*diff_old(0,i,is))
               enddo
            end do

         else
            
c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
            call get_spec_visc_terms(scal_new(0,:,:),beta_old(0,:,:),
     &                               diff_hat(0,:,FirstSpec:),
     &                               spec_flux_lo(0,:,:),
     &                               spec_flux_hi(0,:,:),
     &                               dx(0),lo(0),hi(0))

c     update species with conservative diffusion fluxes
            do i=lo(0),hi(0)
               do n=1,Nspec
                  is = FirstSpec + n - 1
                  scal_new(0,i,is) = scal_old(0,i,is) + 
     $                 dt(0)*(aofs(0,i,is) + I_R(0,i,n)
     $                 + 0.5d0*diff_old(0,i,is) + 0.5d0*diff_hat(0,i,is))
               end do
            end do
            call set_bc_s(scal_new(0,:,:),lo(0),hi(0),bc(0,:))
         
c     calculate differential diffusion
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
            call get_diffdiff_terms(scal_old(0,:,:),scal_new(0,:,:),
     $                              spec_flux_lo(0,:,:),
     $                              spec_flux_hi(0,:,:),beta_old(0,:,:),
     $                              diffdiff_new(0,:),dx(0),lo(0),hi(0))

c     add differential diffusion to forcing for enthalpy solve
            do i=lo(0),hi(0)
               dRhs(0,i,0) = dRhs(0,i,0) 
     $              + 0.5d0*dt(0)*(diffdiff_old(0,i) + diffdiff_new(0,i))
            end do
            
         end if

c     compute RHS for enthalpy diffusion solve
         call update_rhoh(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                    alpha(0,:),beta_old(0,:,:),
     &                    dRhs(0,:,0),Rhs(0,:,RhoH),dx(0),dt(0),
     &                    be_cn_theta,lo(0),hi(0),bc(0,:))

c     update enthalpy with diffusion solve
         rho_flag = 2
         call cn_solve(scal_new(0,:,:),alpha(0,:),beta_old(0,:,:),
     $                 Rhs(0,:,RhoH),dx(0),dt(0),RhoH,be_cn_theta,rho_flag,
     $                 .false.,lo(0),hi(0),bc(0,:))

c     extract D for RhoH
         do i=lo(0),hi(0)
            diff_hat(0,i,RhoH) = 2.d0*((scal_new(0,i,RhoH)-scal_old(0,i,RhoH))/dt(0) 
     $           - aofs(0,i,RhoH) - dRhs(0,i,0)/dt(0) - 0.5d0*diff_old(0,i,RhoH) )
         enddo

         print *,'... react with constant sources'
         do n = 1,nscal
            do i=lo(0),hi(0)
               const_src(0,i,n) = aofs(0,i,n) 
     $              + 0.5d0*diff_hat(0,i,n) + 0.5d0*diff_old(0,i,n)
               lin_src_old(0,i,n) = 0.d0
               lin_src_new(0,i,n) = 0.d0
            enddo
         enddo
      
c     add differential diffusion
         do i=lo(0),hi(0)
            const_src(0,i,RhoH) = const_src(0,i,RhoH)
     $           + 0.5d0*(diffdiff_old(0,i)+diffdiff_new(0,i))
         end do
         
         call strang_chem(scal_old(0,:,:),scal_new(0,:,:),
     $                    const_src(0,:,:),lin_src_old(0,:,:),
     $                    lin_src_new(0,:,:),
     $                    I_R(0,:,:),dt(0),lo(0),hi(0),bc(0,:))

C----------------------------------------------------------------
c     End initial predictor
C----------------------------------------------------------------

C----------------------------------------------------------------
c     Begin MISDC iterations
C----------------------------------------------------------------

c     diffusion solves in SDC iterations are iterative corrections
c     that have a backward Euler character
         be_cn_theta = 1.d0

         do misdc = 1, misdc_iterMAX
            print *,'... doing SDC iter ',misdc
            
            if (fancy_dpdt_fix .eq. 1) then
               
               call compute_pthermo(scal_new(0,:,:),lo(0),hi(0),bc(0,:))
               
               do i=lo(0),hi(0)
                  do n = 1,Nspec
                     is = FirstSpec + n - 1
                     Y(n) = scal_new(0,i,is)/scal_new(0,i,Density)
                  enddo
c     compute 1/gamma
                  call CKMMWY(Y,IWRK,RWRK,mwmix)
                  call CKRP(IWRK,RWRK,Runiv,dummy,dummy) 
                  call CKCPBS(scal_new(0,i,Temp),Y,IWRK,RWRK,cp)
                  
                  gamma_inv = (cp - Runiv/mwmix)/cp
                  
c     delta_chi = delta_chi + (1/gamma)*(ptherm-p0)/(dt*ptherm)
                  delta_chi(0,i) = delta_chi(0,i) 
     $                 + gamma_inv*(scal_new(0,i,RhoRT)-pcgs)/(dt(0)*pcgs)
                  
                  divu_eff(0,i) = divu_extrap(0,i) + delta_chi(0,i)
               end do
               
               call macproj(macvel(0,:),scal_old(0,:,Density),divu_eff(0,:),dx,
     &                      lo(0),hi(0),bc(0,:))
               
            end if
            
            print *,'... compute diff_new = D(U^{n+1,k-1})'
c     this computes rho D_m     (for species)
c                   lambda / cp (for enthalpy)
c                   lambda      (for temperature) 
            call calc_diffusivities(scal_new(0,:,:),beta_new(0,:,:),
     &                              mu_dummy(0,:),lo(0),hi(0))
c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
            call get_spec_visc_terms(scal_new(0,:,:),beta_new(0,:,:),
     &                               diff_new(0,:,FirstSpec:),
     &                               spec_flux_lo(0,:,:),
     &                               spec_flux_hi(0,:,:),
     &                               dx(0),lo(0),hi(0))
c     compute del dot lambda/cp grad h (no differential diffusion)
            call get_rhoh_visc_terms(scal_new(0,:,:),beta_new(0,:,:),
     &                               diff_new(0,:,RhoH),dx(0),lo(0),hi(0))

c     calculate differential diffusion
            if (LeEQ1 .eq. 0) then
c     calculate sum_m del dot h_m (rho D_m - lambda/cp) grad Y_m
c     we pass in conservative rho D grad Y via spec_flux
c     we take lambda / cp from beta
c     we compute h_m from the first scal argument
c     we take the gradient of Y from the second scal argument
               call get_diffdiff_terms(scal_new(0,:,:),scal_new(0,:,:),
     $                                 spec_flux_lo(0,:,:),
     $                                 spec_flux_hi(0,:,:),beta_new(0,:,:),
     $                                 diffdiff_new(0,:),dx(0),lo(0),hi(0))
            end if

            print *,'... computing A forcing term = D^n + I_R^k-1'
            do i=lo(0),hi(0)
               do n = 1,Nspec
                  is = FirstSpec + n - 1
                  tforce(0,i,is) = diff_old(0,i,is) + I_R(0,i,n)
               enddo
c     really no need to recompute this since it doesn't change
               tforce(0,i,RhoH) = diff_old(0,i,RhoH) + diffdiff_old(0,i)
            enddo
            
            print *,'... compute A with updated D+R source'
            call scal_aofs(scal_old(0,:,:),macvel(0,:),aofs(0,:,:),
     $                     divu_eff(0,:),tforce(0,:,:),dx(0),dt(0),
     $                     lo(0),hi(0),bc(0,:))

            print *,'... update rho'
            call update_rho(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                      dt(0),lo(0),hi(0),bc(0,:))

            print *,'... update D for species with A + R + MISDC(D)'
            do i=lo(0),hi(0)
               do n=1,Nspec
                  is = FirstSpec + n - 1
c     includes deferred correction term for species
                  dRhs(0,i,n) = dt(0)*(I_R(0,i,n) 
     &                 + 0.5d0*(diff_old(0,i,is) - diff_new(0,i,is)))
               enddo
c     includes deferred correction term for enthalpy
c     differential diffusion will be added later
               dRhs(0,i,0) = dt(0)*(
     &              + 0.5d0*(diff_old(0,i,RhoH) - diff_new(0,i,RhoH)))
            enddo
            call update_spec(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                       alpha(0,:),beta_old(0,:,:),
     &                       dRhs(0,0:,1:),Rhs(0,0:,FirstSpec:),
     &                       dx(0),dt(0),be_cn_theta,lo(0),hi(0),bc(0,:))

            rho_flag = 2
            do n=1,Nspec
               is = FirstSpec + n - 1
               call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                       Rhs(0,:,is),dx(0),dt(0),is,be_cn_theta,
     $                       rho_flag,.false.,lo(0),hi(0),bc(0,:))
            enddo
            
            if (LeEQ1 .eq. 1) then

c     simply extract D for RhoX
               do i=lo(0),hi(0)
                  do n=1,Nspec
                     is = FirstSpec + n - 1
                     diff_hat(0,i,is) = (scal_new(0,i,is)-scal_old(0,i,is))/dt(0) 
     $                    - aofs(0,i,is) - dRhs(0,i,n)/dt(0)
                  enddo
               enddo

            else

c     compute del dot rho D grad Y and make it conservative
c     save species fluxes for differential diffusion
               call get_spec_visc_terms(scal_new(0,:,:),beta_new(0,:,:),
     &                                  diff_hat(0,:,FirstSpec:),
     &                                  spec_flux_lo(0,:,:),
     &                                  spec_flux_hi(0,:,:),
     &                                  dx(0),lo(0),hi(0))

c     add differential diffusion to forcing for enthalpy solve
               do i=lo(0),hi(0)
                  dRhs(0,i,0) = dRhs(0,i,0) 
     $                 + 0.5d0*dt(0)*(diffdiff_old(0,i) + diffdiff_new(0,i))
               end do

            end if

            print *,'... update D for rhoh with A + R + MISDC(D)'
            call update_rhoh(scal_old(0,:,:),scal_new(0,:,:),aofs(0,:,:),
     &                       alpha(0,:),beta_old(0,:,:),
     &                       dRhs(0,:,0),Rhs(0,:,RhoH),dx(0),dt(0),
     &                       be_cn_theta,lo(0),hi(0),bc(0,:))
            rho_flag = 2
            call cn_solve(scal_new(0,:,:),alpha(0,:),beta_new(0,:,:),
     $                    Rhs(0,:,RhoH),dx(0),dt(0),RhoH,be_cn_theta,
     $                    rho_flag,.false.,lo(0),hi(0),bc(0,:))
            
c     extract D for RhoH
            do i=lo(0),hi(0)
               diff_hat(0,i,RhoH) = (scal_new(0,i,RhoH)-scal_old(0,i,RhoH))/dt(0) 
     $              - aofs(0,i,RhoH) - dRhs(0,i,0)/dt(0)
            enddo
            
            print *,'... react with const sources'
            do n = 1,nscal
               do i=lo(0),hi(0)
                  const_src(0,i,n) = aofs(0,i,n)
     $                 + 0.5d0*(diff_old(0,i,n)+diff_new(0,i,n))
     $                 + diff_hat(0,i,n) - diff_new(0,i,n)
                  lin_src_old(0,i,n) = 0.d0
                  lin_src_new(0,i,n) = 0.d0
               enddo
            enddo
         
c     add differential diffusion
            do i=lo(0),hi(0)
               const_src(0,i,RhoH) = const_src(0,i,RhoH)
     $              + 0.5d0*(diffdiff_old(0,i)+diffdiff_new(0,i))
            end do
            call strang_chem(scal_old(0,:,:),scal_new(0,:,:),
     $                       const_src(0,:,:),lin_src_old(0,:,:),
     $                       lin_src_new(0,:,:),
     $                       I_R(0,:,:),dt(0),lo(0),hi(0),bc(0,:))
            
C----------------------------------------------------------------
c     End MISDC iterations
C----------------------------------------------------------------

         enddo

      end if

      if (use_strang) then

c     omegadot for divu computation is average omegadot
c     over both strang calls
         I_R_divu = I_R

      else

c     omegadot for divu computation is instantaneous
c     value at t^{n+1}
         do i=lo(0),hi(0)
            do n=1,Nspec
               C(n) = scal_new(0,i,FirstSpec+n-1)*invmwt(n)
            end do
            call CKWC(scal_new(0,i,Temp),C,IWRK,RWRK,WDOTK)
            do n=1,Nspec
               I_R_divu(0,i,n) = WDOTK(n)*mwt(n)
            end do
         end do

      end if

c     this computes rho D_m     (for species)
c                   lambda / cp (for enthalpy)
c                   lambda      (for temperature)         
      call calc_diffusivities(scal_new(0,:,:),beta_new(0,:,:),
     &                        mu_new(0,:),lo(0),hi(0))  
      call calc_divu(scal_new(0,:,:),beta_new(0,:,:),I_R_divu(0,:,:),
     &               divu_new(0,:),dx(0),lo(0),hi(0))

      do i=lo(0),hi(0)
         rhohalf(0,i) = 
     $        0.5d0*(scal_old(0,i,Density)+scal_new(0,i,Density))
         dsdt(0,i) = (divu_new(0,i) - divu_old(0,i)) / dt(0)
      enddo

      print *,'... update velocities'

      vel_theta = 0.5d0

c     get velocity visc terms to use as a forcing term for advection
      call get_vel_visc_terms(vel_old(0,:),mu_old(0,:),visc(0,:),dx(0),
     $                        lo(0),hi(0))

      do i=lo(0),hi(0)
         visc(0,i) = visc(0,i)/scal_old(0,i,Density)
      enddo

      call vel_edge_states(vel_old(0,:),scal_old(0,:,Density),gp(0,:),
     $                     macvel(0,:),veledge(0,:),dx(0),dt(0),
     $                     visc(0,:),lo(0),hi(0),bc(0,:))
      
      call update_vel(vel_old(0,:),vel_new(0,:),gp(0,:),rhohalf(0,:),
     &                macvel(0,:),veledge(0,:),alpha(0,:),mu_old(0,:),
     &                vel_Rhs(0,:),dx(0),dt(0),vel_theta,
     &                lo(0),hi(0),bc(0,:))

      if (is_first_initial_iter .eq. 1) then
         call get_vel_visc_terms(vel_old(0,:),mu_old(0,:),visc(0,:),
     $                           dx(0),lo(0),hi(0))
         do i=lo(0),hi(0)
            vel_new(0,i) = vel_new(0,i) + visc(0,i)*dt(0)/rhohalf(0,i)
         enddo
      else
         rho_flag = 1
         call cn_solve(vel_new(0,:),alpha(0,:),mu_new(0,:),
     $                 vel_Rhs(0,:),dx(0),dt(0),1,vel_theta,rho_flag,
     $                 .true.,lo(0),hi(0),bc(0,:))
      endif

      call compute_pthermo(scal_new(0,:,:),lo(0),hi(0),bc(0,:))

      if (fancy_dpdt_fix .eq. 0) then
         call add_dpdt_nodal(scal_new(0,:,:),scal_new(0,:,RhoRT),
     &                       divu_new(0,:),vel_new(0,:),dx(0),dt(0),
     &                       lo(0),hi(0),bc(0,:))
      end if

      print *,'...nodal projection...'
      call project_level(vel_new(0,:),rhohalf(0,:),divu_new(0,:),
     &                   press_old(0,:),press_new(0,:),dx(0),dt(0),
     &                   lo(0),hi(0),bc(0,:))

      end
