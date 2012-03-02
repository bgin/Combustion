      subroutine project(vel_new,rhohalf,divu,
     $                   press_old,press_new,dx,dt,time)
      implicit none
      include 'spec.h'
      real*8  vel_new(-1:nx)
      real*8  rhohalf(0:nx-1)
      real*8 divu(0 :nx-1)
      real*8 press_old(0 :nx)
      real*8 press_new(0 :nx)
      real*8 dx
      real*8 dt, time
      
      integer i
      real*8 phi(0:nx)
      real*8 vel_star(0:nx-1)
      real*8 divu_node
      real*8 gp

      if (dt .gt. 0) then
         
         ! project v_star = v^n+1 + dt*gp^old/rho
         do i = 0,nx-1
            gp = (press_old(i+1)-press_old(i))/dx
            vel_star(i) = vel_new(i) + dt * gp / rhohalf(i)
         end do
      else
         
         ! project v^n+1
         do i = 0,nx-1
            vel_star(i) = vel_new(i)
         end do
      endif

c     Build v^n+1 directly, since we have bc and div(v)=s
c     Get boundary value, vel(-1) at inlet wall, and integrate explicitly.
      call set_bc_v(vel_new,dx,time)
      vel_new(0) = vel_new(-1) + 0.5*divu(0)*dx
      do i = 1,nx-1
         divu_node = (divu(i) + divu(i-1))*0.5d0
         vel_new(i) = vel_new(i-1) + divu_node*dx
      end do
      
      if (dt .gt. 0.) then

c     For this projection, v^n+1 = (v_star + dt*gp^old/rho) - dt*gp^new/rho
c     and gp = -(v_new-v_old)/dt * rhohalf
         phi(nx) = 0.d0
         do i = nx-1,0,-1
            gp = -(vel_new(i) - vel_star(i))/dt * rhohalf(i)
            phi(i) = phi(i+1) - gp*dx
         enddo
         do i = 0,nx
            press_new(i) = phi(i)
         enddo

      else

c     set pressure to zero since we are not keeping it
         do i = 0,nx
            press_new(i) = 0.d0
         enddo

      endif

c     also need to set outflow boundary
      call set_bc_v(vel_new,dx,time)

      end
