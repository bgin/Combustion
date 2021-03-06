! reference: McCorqudale and Colella, 2011, CAMCoS, 6, 1

subroutine rns_fill_rk4_bndry (lo, hi,  &
     uu, uu_l1, uu_l2, uu_h1, uu_h2, &
     u0, u0_l1, u0_l2, u0_h1, u0_h2, &
     k1, k1_l1, k1_l2, k1_h1, k1_h2, &
     k2, k2_l1, k2_l2, k2_h1, k2_h2, &
     k3, k3_l1, k3_l2, k3_h1, k3_h2, &
     k4, k4_l1, k4_l2, k4_h1, k4_h2, &
     dtdt, xsi, stage)
  use meth_params_module
  implicit none
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) :: uu_l1, uu_l2, uu_h1, uu_h2
  integer, intent(in) :: u0_l1, u0_l2, u0_h1, u0_h2
  integer, intent(in) :: k1_l1, k1_l2, k1_h1, k1_h2
  integer, intent(in) :: k2_l1, k2_l2, k2_h1, k2_h2
  integer, intent(in) :: k3_l1, k3_l2, k3_h1, k3_h2
  integer, intent(in) :: k4_l1, k4_l2, k4_h1, k4_h2
  integer, intent(in) :: stage
  double precision, intent(in) :: dtdt, xsi
  double precision, intent(inout) :: uu(uu_l1:uu_h1,uu_l2:uu_h2,NVAR)
  double precision, intent(in   ) :: u0(u0_l1:u0_h1,u0_l2:u0_h2,NVAR)
  double precision, intent(in   ) :: k1(k1_l1:k1_h1,k1_l2:k1_h2,NVAR)
  double precision, intent(in   ) :: k2(k2_l1:k2_h1,k2_l2:k2_h2,NVAR)
  double precision, intent(in   ) :: k3(k3_l1:k3_h1,k3_l2:k3_h2,NVAR)
  double precision, intent(in   ) :: k4(k4_l1:k4_h1,k4_l2:k4_h2,NVAR)

  integer :: i, j, n
  double precision :: xsi2, xsi3, dtdt2, dtdt3
  double precision :: b1, b2, b3, b4
  double precision :: c1, c2, c3, c4
  double precision :: d1, d2, d3, d4
  double precision :: e1, e2, e3, e4
  double precision :: Ut(lo(1):hi(1)), Utt(lo(1):hi(1)), Uttt(lo(1):hi(1))

  xsi2 = xsi*xsi
  xsi3 = xsi2*xsi

  dtdt2 = dtdt*dtdt
  dtdt3 = dtdt2*dtdt

  ! coefficients for U
  b1 = xsi - 1.5d0*xsi2 + (2.d0/3.d0)*xsi3
  b2 = xsi2 - (2.d0/3.d0)*xsi3
  b3 = b2
  b4 = -0.5d0*xsi2 + (2.d0/3.d0)*xsi3

  ! coefficients for Ut
  c1 = 1.d0 - 3.d0*xsi + 2.d0*xsi2
  c2 = 2.d0*xsi - 2.d0*xsi2
  c3 = c2
  c4 = -xsi + 2.d0*xsi2

  ! coefficients for Utt
  d1 = -3.d0 + 4.d0*xsi
  d2 =  2.d0 - 4.d0*xsi
  d3 =  d2
  d4 = -1.d0 + 4.d0*xsi

  ! coefficients for Uttt
  e1 =  4.d0
  e2 = -4.d0
  e3 = -4.d0
  e4 =  4.d0

  !$omp parallel do collapse(2) private(i,j,n,Ut,Utt,Uttt)
  do n=1,NVAR
     do j=lo(2),hi(2)

        do i=lo(1),hi(1)
           uu(i,j,n) = u0(i,j,n)+b1*k1(i,j,n)+b2*k2(i,j,n)+b3*k3(i,j,n)+b4*k4(i,j,n)
        end do

        if (stage .eq. 0) cycle

        do i=lo(1),hi(1)
           Ut(i) = c1*k1(i,j,n)+c2*k2(i,j,n)+c3*k3(i,j,n)+c4*k4(i,j,n)
        end do

        if (stage .eq. 1) then
           
           do i=lo(1),hi(1)
              uu(i,j,n) = uu(i,j,n) + 0.5d0*dtdt*Ut(i)
           end do
           
        else

           do i=lo(1),hi(1)
              Utt (i) = d1*k1(i,j,n)+d2*k2(i,j,n)+d3*k3(i,j,n)+d4*k4(i,j,n)
              Uttt(i) = e1*k1(i,j,n)+e2*k2(i,j,n)+e3*k3(i,j,n)+e4*k4(i,j,n)
           end do

           if (stage .eq. 2) then

              do i=lo(1),hi(1)
                 uu(i,j,n) = uu(i,j,n) + 0.5d0*dtdt*Ut(i) + 0.25d0*dtdt2*Utt(i) &
                      + 0.0625d0*dtdt3*(Uttt(i)-4.d0*(k3(i,j,n)-k2(i,j,n)))
              end do

           else if (stage .eq. 3) then

              do i=lo(1),hi(1)
                 uu(i,j,n) = uu(i,j,n) + dtdt*Ut(i) + 0.5d0*dtdt2*Utt(i) &
                      + 0.125d0*dtdt3*(Uttt(i)+4.d0*(k3(i,j,n)-k2(i,j,n)))
              end do              

           end if

        end if

     end do
  end do
  !$omp end parallel do

end subroutine rns_fill_rk4_bndry


subroutine rns_fill_rk3_bndry (lo, hi,  &
     uu, uu_l1, uu_l2, uu_h1, uu_h2, &
     u0, u0_l1, u0_l2, u0_h1, u0_h2, &
     k1, k1_l1, k1_l2, k1_h1, k1_h2, &
     k2, k2_l1, k2_l2, k2_h1, k2_h2, &
     k3, k3_l1, k3_l2, k3_h1, k3_h2, &
     dtdt, xsi, stage)
  use meth_params_module
  implicit none
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) :: uu_l1, uu_l2, uu_h1, uu_h2
  integer, intent(in) :: u0_l1, u0_l2, u0_h1, u0_h2
  integer, intent(in) :: k1_l1, k1_l2, k1_h1, k1_h2
  integer, intent(in) :: k2_l1, k2_l2, k2_h1, k2_h2
  integer, intent(in) :: k3_l1, k3_l2, k3_h1, k3_h2
  integer, intent(in) :: stage
  double precision, intent(in) :: dtdt, xsi
  double precision, intent(inout) :: uu(uu_l1:uu_h1,uu_l2:uu_h2,NVAR)
  double precision, intent(in   ) :: u0(u0_l1:u0_h1,u0_l2:u0_h2,NVAR)
  double precision, intent(in   ) :: k1(k1_l1:k1_h1,k1_l2:k1_h2,NVAR)
  double precision, intent(in   ) :: k2(k2_l1:k2_h1,k2_l2:k2_h2,NVAR)
  double precision, intent(in   ) :: k3(k3_l1:k3_h1,k3_l2:k3_h2,NVAR)

  integer :: i, j, n
  double precision :: xsi2, dtdt2
  double precision :: b1, b2, b3
  double precision :: c1, c2, c3
  double precision :: d1, d2, d3
  double precision :: Ut(lo(1):hi(1))

  xsi2 = xsi*xsi

  dtdt2 = dtdt*dtdt

  ! coefficients for U
  b1 = xsi - (5.d0/6.d0)*xsi2
  b2 = (1.d0/6.d0)*xsi2
  b3 = (2.d0/3.d0)*xsi2

  ! coefficients for Ut
  c1 = 1.d0 - (5.d0/3.d0)*xsi
  c2 = (1.d0/3.d0)*xsi
  c3 = (4.d0/3.d0)*xsi

  ! coefficients for Utt
  d1 = -(5.d0/3.d0)
  d2 =  (1.d0/3.d0)
  d3 =  (4.d0/3.d0)

  !$omp parallel do collapse(2) private(i,j,n,Ut)
  do n=1,NVAR
     do j=lo(2),hi(2)

        do i=lo(1),hi(1)
           uu(i,j,n) = u0(i,j,n)+b1*k1(i,j,n)+b2*k2(i,j,n)+b3*k3(i,j,n)
        end do

        if (stage .eq. 0) cycle

        do i=lo(1),hi(1)
           Ut(i) = c1*k1(i,j,n)+c2*k2(i,j,n)+c3*k3(i,j,n)
        end do

        if (stage .eq. 1) then
           
           do i=lo(1),hi(1)
              uu(i,j,n) = uu(i,j,n) + dtdt*Ut(i)
           end do
           
        else if (stage .eq. 2) then

           do i=lo(1),hi(1)
              uu(i,j,n) = uu(i,j,n) + 0.5d0*dtdt*Ut(i) &
                   + 0.25d0*dtdt2*(d1*k1(i,j,n)+d2*k2(i,j,n)+d3*k3(i,j,n))
           end do

        end if

     end do
  end do
  !$omp end parallel do

end subroutine rns_fill_rk3_bndry
