      subroutine vel_edge_states(vel_old,rho_old,gp,
     $                           macvel,sedge,dx,dt,tforces,lo,hi)
      implicit none
      include 'spec.h'
      real*8  vel_old(-2:nx+1)
      real*8  rho_old(-2:nx+1)
      real*8       gp(-1:nx)
      real*8   macvel(0:nx)
      real*8    sedge(0:nx)
      real*8 dx, dt
      real*8  tforces(-1:nx)
      integer lo, hi

      real*8 slope(-1:nx)
      real*8 dth
      real*8 dthx
      real*8 eps
      real*8 slo,shi
      integer i
      
      dth  = 0.5d0 * dt
      dthx = 0.5d0 * dt / dx
      eps = 1.e-6*vel_TYP

      call mkslopes(vel_old,slope)

      do i=lo+1,hi
         slo = vel_old(i-1) + (0.5 - dthx*vel_old(i-1))*slope(i-1)
     $        - dth*gp(i-1)/rho_old(i-1) + dth*tforces(i-1)
         shi = vel_old(i  ) - (0.5 + dthx*vel_old(i))*slope(i  )
     $        - dth*gp(i  )/rho_old(i  ) + dth*tforces(i)
         if ( macvel(i) .gt. eps) then
            sedge(i) = slo
         else if ( macvel(i) .lt. -eps) then
            sedge(i) = shi
         else if ( abs(macvel(i)) .le. eps) then
            sedge(i) = 0.5d0 * (slo + shi)
         endif
      enddo
      
      sedge(0) = vel_old(-1)
      
      i = nx
      sedge(i) = vel_old(i-1) + 
     $     (0.5d0 - dthx*vel_old(i-1))*slope(i-1) 
     $     - dth*gp(i-1)/rho_old(i-1)

      end
      
