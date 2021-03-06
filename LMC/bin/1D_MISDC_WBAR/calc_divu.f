      subroutine calc_divu(scal,beta,I_R,divu,dx,lo,hi)
      implicit none
      include 'spec.h'

c     Quantities passed in
      real*8 scal(-2:nfine+1,nscal)
      real*8 beta         (-1:nfine  ,nscal)
      real*8  I_R(-1:nfine  ,0:Nspec)
      real*8 divu(-1:nfine)
      real*8 dx
      integer lo,hi
      
      real*8 Y(Nspec)
      real*8 HK(Nspec)
      real*8 cpmix,mwmix
      
      real*8 diff(-1:nfine,nscal)

      real*8 RWRK,rho,T
      integer IWRK,i,n

      real*8 gamma_lo     (0:nfine-1,Nspec)
      real*8 gamma_hi     (0:nfine-1,Nspec)
      real*8 gamma_Wbar_lo(0:nfine-1,Nspec)
      real*8 gamma_Wbar_hi(0:nfine-1,Nspec)
      real*8 beta_for_Wbar(-1:nfine ,nscal)

      call compute_beta_for_Wbar(scal,beta,beta_for_Wbar,lo,hi)

      call get_temp_visc_terms(scal,beta,beta_for_Wbar,diff(:,Temp),dx,lo,hi)
      call get_spec_visc_terms(scal,beta,gamma_lo,gamma_hi,lo,hi)
      call get_spec_visc_terms_Wbar(scal,beta_for_Wbar,
     &                              gamma_Wbar_lo,gamma_Wbar_hi,lo,hi)

c     add Wbar part
      gamma_lo = gamma_lo + gamma_Wbar_lo
      gamma_hi = gamma_hi + gamma_Wbar_hi

      call adjust_spec_diffusion_fluxes(scal,gamma_lo,gamma_hi,lo,hi)
      call flux_divergence(diff(:,FirstSpec),gamma_lo,gamma_hi,dx,lo,hi)

      do i=lo,hi
         rho = scal(i,Density)
         do n = 1,Nspec
            Y(n) = scal(i,FirstSpec + n - 1) / rho
         enddo
         T = scal(i,Temp)
         call CKMMWY(Y,IWRK,RWRK,mwmix)
         call CKCPBS(T,Y,IWRK,RWRK,cpmix)
         call CKHMS(T,IWRK,RWRK,HK)

         divu(i) = diff(i,Temp)/(rho*cpmix*T)

         do n=1,Nspec
            divu(i) = divu(i)
     &           + (diff(i,FirstSpec+n-1) + I_R(i,n))
     &           *invmwt(n)*mwmix/rho - HK(n)*I_R(i,n)/(rho*cpmix*T)
         enddo
       enddo

      end
