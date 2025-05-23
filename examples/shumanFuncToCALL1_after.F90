!#PYFT transfo: --shumanFUNCtoCALL

!MNH_LIC Copyright 1994-2021 CNRS, Meteo-France and Universite Paul Sabatier
!MNH_LIC This is part of the Meso-NH software governed by the CeCILL-C licence
!MNH_LIC version 1. See LICENSE, CeCILL-C_V1-en.txt and CeCILL-C_V1-fr.txt
!MNH_LIC for details. version 1.
!-----------------------------------------------------------------
MODULE MODE_TURB_HOR_DYN_CORR
IMPLICIT NONE
CONTAINS
      SUBROUTINE TURB_HOR_DYN_CORR(D,TURBN,TLES,KSPLT, PTSTEP,       &
                      KRR, KSV,OFLAT,O2D,                            &
                      TPFILE,                                        &
                      PK,PINV_PDZZ,                                  &
                      PDXX,PDYY,PDZZ,PDZX,PDZY,PZZ,                  &
                      PDIRCOSZW,                                     &
                      PCOSSLOPE,PSINSLOPE,                           &
                      PRHODJ,                                        &
                      PCDUEFF,PTAU11M,PTAU12M,PTAU22M,PTAU33M,       &
                      PUM,PVM,PWM,PUSLOPEM,PVSLOPEM,                 &
                      PTHLM,PRM,PSVM,                                &
                      PTKEM,PLM,                                     &
                      PDP,PTP,                                       &
                      PRUS,PRVS,PRWS                                 )
!     ################################################################
!
!!****  *TURB_HOR* -routine to compute the source terms in the meso-NH
!!               model equations due to the non-vertical turbulent fluxes.
!!
!!    PURPOSE
!!    -------
!!
!!     see TURB_HOR
!!
!!**  METHOD
!!    ------
!!
!!    EXTERNAL
!!    --------
!!
!!    IMPLICIT ARGUMENTS
!!    ------------------
!!
!!    REFERENCE
!!    ---------
!!
!!    AUTHOR
!!    ------
!!
!!      Joan Cuxart             * INM and Meteo-France *
!!
!!    MODIFICATIONS
!!    -------------
!!                     Aug    , 1997 (V. Saravane) spliting of TURB_HOR
!!                     Nov  27, 1997 (V. Masson) clearing of the routine
!!                     Oct  18, 2000 (V. Masson) LES computations + OFLAT switch
!!                     Feb  15, 2001 (J. Stein)  remove the use of w=0 at the
!!                                               ground   
!!                     Mar  12, 2001 (V. Masson and J. Stein) major bugs 
!!                                 + change of discretization at the surface
!!                     Nov  06, 2002 (V. Masson) LES budgets
!!                     October 2009 (G. Tanguy) add ILENCH=LEN(YCOMMENT) after
!!                                              change of YCOMMENT
!!                     July 2012     (V.Masson) Implicitness of W
!!                     March 2014    (V.Masson) tridiag_w : bug between
!!                                               mass and flux position
!!                     J.Escobar : 15/09/2015 : WENO5 & JPHEXT <> 1
!!                      M.Moge  04/2016 Use openACC directives to port the TURB part of Meso-NH on GPU
!!  Philippe Wautelet: 05/2016-04/2018: new data structures and calls for I/O
!  P. Wautelet 20/05/2019: add name argument to ADDnFIELD_ll + new ADD4DFIELD_ll subroutine
!  J.Escobar 13/08/2020: PGI/NVHPC BUG , extend DO CONCURRENT to 3D indexes        
!! --------------------------------------------------------------------------
!
!*      0. DECLARATIONS
!          ------------
!
USE MODD_TURB_n, ONLY: TURB_t
USE MODD_DIMPHYEX,   ONLY: DIMPHYEX_t
!
USE MODD_ARGSLIST_ll,    ONLY: LIST_ll
USE MODD_CST
USE MODD_CTURB
use modd_field,          only: tfieldmetadata, TYPEREAL
USE MODD_IO,             ONLY: TFILEDATA
USE MODD_PARAMETERS
USE MODD_LES, ONLY: TLES_t
!
USE MODE_ll
USE MODE_IO_FIELD_WRITE, ONLY: IO_FIELD_WRITE
!
USE MODI_GRADIENT_M
USE MODI_GRADIENT_U
USE MODI_GRADIENT_V
USE MODI_GRADIENT_W
USE MODI_SHUMAN
USE MODE_SHUMAN_PHY
USE MODE_GRADIENT_M_PHY, ONLY: GZ_M_W_PHY
USE MODE_GRADIENT_W_PHY, ONLY: GZ_W_M_PHY, GZ_W_M_PHY
USE MODE_GRADIENT_V_PHY, ONLY: GY_V_M_PHY
USE MODE_GRADIENT_U_PHY, ONLY: GX_U_M_PHY
USE MODE_COEFJ, ONLY: COEFJ
#ifdef MNH_OPENACC
USE MODI_GET_HALO
#endif
USE MODI_LES_MEAN_SUBGRID
USE MODE_TRIDIAG_W, ONLY: TRIDIAG_W
!
USE MODI_SECOND_MNH
USE MODE_MPPDB
!
IMPLICIT NONE
!
!
!*       0.1  declaration of arguments
!
!
!
TYPE(DIMPHYEX_t),         INTENT(IN)    :: D
TYPE(TURB_t),             INTENT(IN)    :: TURBN
TYPE(TLES_t),             INTENT(INOUT) :: TLES          ! modd_les structure
INTEGER,                  INTENT(IN)    ::  KSPLT        ! split process index
REAL,                     INTENT(IN)    ::  PTSTEP       ! timestep
INTEGER,                  INTENT(IN)    ::  KRR          ! number of moist var.
INTEGER,                  INTENT(IN)    ::  KSV          ! number of sv var.
LOGICAL,                  INTENT(IN)    ::  OFLAT        ! Logical for zero ororography
LOGICAL,                  INTENT(IN)    ::  O2D          ! Logical for 2D model version (modd_conf)
TYPE(TFILEDATA),          INTENT(INOUT)    ::  TPFILE       ! Output file
!
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PK          ! Turbulent diffusion doef.
                                                        ! PK = PLM * SQRT(PTKEM)
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PINV_PDZZ   ! 1./PDZZ
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PDXX, PDYY, PDZZ, PDZX, PDZY 
                                                         ! Metric coefficients
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PZZ          ! vertical grid
REAL, DIMENSION(D%NIT,D%NJT),     INTENT(IN)    ::  PDIRCOSZW
! Director Cosinus along z directions at surface w-point
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PCOSSLOPE       ! cosinus of the angle 
                                      ! between i and the slope vector
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PSINSLOPE       ! sinus of the angle 
                                      ! between i and the slope vector
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PRHODJ       ! density * grid volume
!
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PCDUEFF      ! Cd * || u || at time t
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PTAU11M      ! <uu> in the axes linked 
       ! to the maximum slope direction and the surface normal and the binormal 
       ! at time t - dt
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PTAU12M      ! <uv> in the same axes
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PTAU22M      ! <vv> in the same axes
REAL, DIMENSION(D%NIT,D%NJT),   INTENT(IN)   ::  PTAU33M      ! <ww> in the same axes
!
! Variables at t-1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PUM,PVM,PWM,PTHLM
REAL, DIMENSION(D%NIT,D%NJT,D%NKT,KRR), INTENT(IN)    ::  PRM
REAL, DIMENSION(D%NIT,D%NJT,D%NKT,KSV), INTENT(IN)    ::  PSVM
REAL, DIMENSION(D%NIT,D%NJT),      INTENT(IN)   ::  PUSLOPEM     ! wind component along the 
                                     ! maximum slope direction
REAL, DIMENSION(D%NIT,D%NJT),      INTENT(IN)   ::  PVSLOPEM     ! wind component along the 
                                     ! direction normal to the maximum slope one
!
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PTKEM        ! TKE at time t- dt
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(IN)    ::  PLM          ! Turb. mixing length
!
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(INOUT) ::  PRUS, PRVS, PRWS
REAL, DIMENSION(D%NIT,D%NJT,D%NKT),   INTENT(INOUT) ::  PDP,PTP      ! TKE production terms
!
!
!
!*       0.2  declaration of local variables
!
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) :: ZFLX,ZWORK
    ! work arrays, PK is the turb. mixing coef.
!   
REAL, DIMENSION(D%NIT,D%NJT) ::ZDIRSINZW 
      ! sinus of the angle between the vertical and the normal to the orography
INTEGER             :: IKB,IKE
                                    ! Index values for the Beginning and End
                                    ! mass points of the domain  
INTEGER             :: IKU,IKT,IIT,IJT                                   
INTEGER             :: JSV,JI,JJ,JK          ! scalar loop counter
!
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: GX_U_M_PUM
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: GY_V_M_PVM
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: GZ_W_M_PWM
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: GZ_W_M_ZWP
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: ZMZF_DZZ   ! MZF(PDZZ)
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: ZDFDDWDZ   ! formal derivative of the 
!                                                                   ! flux (variable: dW/dz)
REAL, DIMENSION(D%NIT,D%NJT,D%NKT)  :: ZWP        ! W at future   time-step
!
REAL, DIMENSION(D%NIT,D%NJT) :: ZDU_DZ_DZS_DX ! du/dz*dzs/dx surf
REAL, DIMENSION(D%NIT,D%NJT) :: ZDV_DZ_DZS_DY ! dv/dz*dzs/dy surf
REAL, DIMENSION(D%NIT,D%NJT) :: ZDU_DX        ! du/dx        surf
REAL, DIMENSION(D%NIT,D%NJT) :: ZDV_DY        ! dv/dy        surf
REAL, DIMENSION(D%NIT,D%NJT) :: ZDW_DZ        ! dw/dz        surf
!
INTEGER                :: IINFO_ll      ! return code of parallel routine
TYPE(LIST_ll), POINTER :: TZFIELDS_ll   ! list of fields to exchange

REAL :: ZTIME1, ZTIME2


REAL, DIMENSION(D%NIT,D%NJT,1+JPVEXT:3+JPVEXT) :: ZCOEFF , ZDZZ
                                    ! coefficients for the uncentred gradient 
                                    ! computation near the ground
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZGX_U_M3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZGY_V_M3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZGZ_W_M3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMZF3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZMXM2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZSHUGRADWK1_2D
REAL, DIMENSION(D%NIT,D%NJT) ::ZMXF2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZMXF2D_WORK2
REAL, DIMENSION(D%NIT,D%NJT) ::ZMYM2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZMYF2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZMYF2D_WORK2
REAL, DIMENSION(D%NIT,D%NJT) ::ZDXF2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT) ::ZDYF2D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZSHUGRADWK1_3D
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZDXM3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMXF3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZDZF3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMZM3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMXM3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZSHUGRADWK2_3D
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMZM3D_WORK2
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZDYM3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMYF3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZMYM3D_WORK1
REAL, DIMENSION(D%NIT,D%NJT,D%NKT) ::ZGZ_M_W3D_WORK1
TYPE(TFIELDMETADATA) :: TZFIELD
! --------------------------------------------------------------------------
!
!*       1.   PRELIMINARY COMPUTATIONS
!             ------------------------
NULLIFY(TZFIELDS_ll)
!
IKB = 1+JPVEXT               
IKE = SIZE(PUM,3)-JPVEXT    
IKU = SIZE(PUM,3)
IIT=D%NIT
IJT=D%NJT
IKT=D%NKT
!
!
!$acc kernels async(1)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDIRSINZW(:,:) = SQRT( 1. - PDIRCOSZW(:,:)**2 )
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL GX_U_M_PHY(D, OFLAT,PUM(:, :, :),PDXX(:, :, :),PDZZ(:, :, :),PDZX(:, :, :), ZGX_U_M3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
GX_U_M_PUM(:, :, :) = ZGX_U_M3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
IF (.NOT. O2D) THEN
  CALL GY_V_M_PHY(D, OFLAT,PVM(:, :, :),PDYY(:, :, :),PDZZ(:, :, :),PDZY(:, :, :), ZGY_V_M3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
GY_V_M_PVM(:, :, :) = ZGY_V_M3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
END IF
CALL GZ_W_M_PHY(D, PWM(:, :, :),PDZZ(:, :, :), ZGZ_W_M3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
GZ_W_M_PWM(:, :, :) = ZGZ_W_M3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
!
CALL MZF_PHY(D, PDZZ(:, :, :), ZMZF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZMZF_DZZ(:, :, :) = ZMZF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
!
CALL ADD3DFIELD_ll( TZFIELDS_ll, ZFLX, 'TURB_HOR_DYN_CORR::ZFLX' )


!  compute the coefficients for the uncentred gradient computation near the 
!  ground
!
!*       9.   < U'U'>
!             -------
!
! Computes the U variance
IF (.NOT. O2D) THEN
   !$acc kernels async(2) present_cr(zflx,gz_w_m_pwm)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZFLX(:,:,:)= (2./3.) * PTKEM(:,:,:)                            &
           - XCMFS * PK(:,:,:) *( (4./3.) * GX_U_M_PUM(:,:,:)        &
           -(2./3.) * ( GY_V_M_PVM(:,:,:)                     &
           +GZ_W_M_PWM(:,:,:)                ) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
   !$acc end kernels
   !!  &   to be tested later
  !!  + XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
ELSE
  !$acc kernels async(2)
  !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  ZFLX(:,:,:)= (2./3.) * PTKEM(:,:,:)                                  &
    - XCMFS * PK(:,:,:) *( (4./3.) * GX_U_M_PUM(:,:,:)                 &
                   -(2./3.) * ( GZ_W_M_PWM(:,:,:)             ) ) 
  !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
  !!  &   to be tested later
  !!  + XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
END IF
!
!$acc kernels async(2)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZFLX(:,:,IKE+1) = ZFLX(:,:,IKE) 
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!* prescription of du/dz and dv/dz with uncentered gradient at the surface
!  prescription of dw/dz at Dz/2 above ground using the continuity equation
!  using a Boussinesq hypothesis to remove the z dependance of rhod_ref
!  (div u = 0)
!
! ZDZZ(:,:,:) = MXM(PDZZ(:,:,IKB:IKB+2)) ! case not handled yet by pyfortool --expandAllArraysConcurrent and shumanFUNCtoCALL
CALL MXM2D_PHY(D, PDZZ(:,:,IKB), ZMXM2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB) = ZMXM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = PDZZ(:,:,IKB+1)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MXM2D_PHY(D, ZSHUGRADWK1_2D, ZMXM2D_WORK1)
!
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB+1) = ZMXM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = PDZZ(:,:,IKB+2)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MXM2D_PHY(D, ZSHUGRADWK1_2D, ZMXM2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB+2) = ZMXM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels async(3) present_cr(zdzz,zcoeff)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZCOEFF(:,:,IKB+2)= - ZDZZ(:,:,2) /      &
        ( (ZDZZ(:,:,3)+ZDZZ(:,:,2)) * ZDZZ(:,:,3) )
   ZCOEFF(:,:,IKB+1)=   (ZDZZ(:,:,3)+ZDZZ(:,:,2)) /      &
        ( ZDZZ(:,:,2) * ZDZZ(:,:,3) )
   ZCOEFF(:,:,IKB)= - (ZDZZ(:,:,3)+2.*ZDZZ(:,:,2)) /      &
        ( (ZDZZ(:,:,3)+ZDZZ(:,:,2)) * ZDZZ(:,:,2) )
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = (ZCOEFF(:,:,IKB+2)*PUM(:,:,IKB+2)        +ZCOEFF(:,:,IKB+1)*PUM(:,:,IKB+1)        +ZCOEFF(:,:,IKB)*PUM(:,:,IKB)       ) * 0.5 * ( PDZX(:,:,IKB+1)+PDZX(:,:,IKB))
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MXF2D_PHY(D, ZSHUGRADWK1_2D, ZMXF2D_WORK1)
CALL MXF2D_PHY(D, PDXX(:,:,IKB), ZMXF2D_WORK2)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDU_DZ_DZS_DX(:,:)=ZMXF2D_WORK1(:, :)/ ZMXF2D_WORK2(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!
CALL MYM2D_PHY(D, PDZZ(:,:,IKB), ZMYM2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB) = ZMYM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = PDZZ(:,:,IKB+1)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MYM2D_PHY(D, ZSHUGRADWK1_2D, ZMYM2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB+1) = ZMYM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = PDZZ(:,:,IKB+2)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MYM2D_PHY(D, ZSHUGRADWK1_2D, ZMYM2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDZZ(:,:,IKB+2) = ZMYM2D_WORK1(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!
!$acc kernels async(4) present_cr(zdzz,zcoeff)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZCOEFF(:,:,IKB+2)= - ZDZZ(:,:,2) /      &
        ( (ZDZZ(:,:,3)+ZDZZ(:,:,2)) * ZDZZ(:,:,3) )
   ZCOEFF(:,:,IKB+1)=   (ZDZZ(:,:,3)+ZDZZ(:,:,2)) /      &
        ( ZDZZ(:,:,2) * ZDZZ(:,:,3) )
   ZCOEFF(:,:,IKB)= - (ZDZZ(:,:,3)+2.*ZDZZ(:,:,2)) /      &
        ( (ZDZZ(:,:,3)+ZDZZ(:,:,2)) * ZDZZ(:,:,2) )
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels

!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZSHUGRADWK1_2D(:, :) = (ZCOEFF(:,:,IKB+2)*PVM(:,:,IKB+2)        +ZCOEFF(:,:,IKB+1)*PVM(:,:,IKB+1)        +ZCOEFF(:,:,IKB)*PVM(:,:,IKB)       ) * 0.5 * ( PDZY(:,:,IKB+1)+PDZY(:,:,IKB))
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL MYF2D_PHY(D, ZSHUGRADWK1_2D, ZMYF2D_WORK1)
CALL MYF2D_PHY(D, PDYY(:,:,IKB), ZMYF2D_WORK2)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDV_DZ_DZS_DY(:,:)=ZMYF2D_WORK1(:, :)/ ZMYF2D_WORK2(:, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!
!
CALL DXF2D_PHY(D, PUM(:,:,IKB), ZDXF2D_WORK1)
CALL MXF2D_PHY(D, PDXX(:,:,IKB), ZMXF2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDU_DX(:,:)=  ZDXF2D_WORK1(:, :) / ZMXF2D_WORK1(:, :)  &
              - ZDU_DZ_DZS_DX(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
CALL DYF2D_PHY(D, PVM(:,:,IKB), ZDYF2D_WORK1)
CALL MYF2D_PHY(D, PDYY(:,:,IKB), ZMYF2D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDV_DY(:,:)=  ZDYF2D_WORK1(:, :) / ZMYF2D_WORK1(:, :) &
              - ZDV_DZ_DZS_DY(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!
!$acc kernels async(4) present_cr(zdv_dy,zdw_dz)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZDW_DZ(:,:)=-ZDU_DX(:,:)-ZDV_DY(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!* computation 
!
!!! wait for the computation of ZFLX
!$acc wait(2) async(4)
!!! wait for the computation of ZDW_DZ
!$acc wait(4)
!
! ! !!! we can launch the update of ZFLX on the part that has already been computed
! ! !$acc update self(ZFLX(:,:,IKB+1:)) async(10)
!attention !!!!! je ne comprends pas pourquoi mais ce update plante à l'execution...
! du coup je ne peux pas faire de update self asynchrone...
!
!$acc kernels async(3) present_cr(zdu_dx,zflx)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZFLX(:,:,IKB)   = (2./3.) * PTKEM(:,:,IKB)                           &
        - XCMFS * PK(:,:,IKB) * 2. * ZDU_DX(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels

!!  &  to be tested later
!! + XCMFB * PLM(:,:,IKB:IKB) /SQRT(PTKEM(:,:,IKB:IKB)) *        &
!!   (-2./3.) * PTP(:,:,IKB:IKB)
!
! extrapolates this flux under the ground with the surface flux
!
!
!!! wait for the computation of ZDIRSINZW
!$acc wait(1)
!
!$acc kernels async(4) present_cr(ZFLX,ZDIRSINZW)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKB-1) =                                                            &
        PTAU11M(:,:) * PCOSSLOPE(:,:)**2 * PDIRCOSZW(:,:)**2                 &
  -2. * PTAU12M(:,:) * PCOSSLOPE(:,:)* PSINSLOPE(:,:) * PDIRCOSZW(:,:)       &
  +     PTAU22M(:,:) * PSINSLOPE(:,:)**2                                     &
  +     PTAU33M(:,:) * PCOSSLOPE(:,:)**2 * ZDIRSINZW(:,:)**2                 &
  +2. * PCDUEFF(:,:) *      (                                                &
      PVSLOPEM(:,:) * PCOSSLOPE(:,:)    * PSINSLOPE(:,:) * ZDIRSINZW(:,:)    &
    - PUSLOPEM(:,:) * PCOSSLOPE(:,:)**2 * ZDIRSINZW(:,:) * PDIRCOSZW(:,:)    )
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
! 
!!! wait for the computation of ZFLX(:,:,IKB) and ZFLX(:,:,IKB-1)
!$acc wait(3) async(4)
!
!$acc kernels async(4)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZFLX(:,:,IKB-1) = 2. * ZFLX(:,:,IKB-1) -  ZFLX(:,:,IKB)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!
!!! wait for the computation of ZFLX(:,:,IKB-1)
!$acc wait(4)
!


! ! !!! we can launch the update of ZFLX on the rest
! ! !$acc update self(ZFLX(:,:,1:IKB)) async(11)
! ! !
! ! !!! and wait for the update self(ZFLX(...)) to complete
! ! !$acc wait(10)
! ! !$acc wait(11)
!attention !!!!! je ne comprends pas pourquoi mais le update self(ZFLX(:,:,IKB+1:)) plante à l'execution...
! du coup je ne peux pas faire de update self asynchrone...


!
!!! at this point there are no more async operations running
!!! to be absolutely sure, we do a wait
!$acc wait
!
#ifndef MNH_OPENACC
CALL UPDATE_HALO_ll(TZFIELDS_ll, IINFO_ll)
#else
CALL GET_HALO_D(ZFLX,HNAME='TURB_HOR_DYN_CORR::ZFLX')
#endif
!
IF ( TPFILE%LOPENED .AND. TURBN%LTURB_FLX ) THEN
  !$acc update self( ZFLX )
  ! stores <U U>  
  TZFIELD = TFIELDMETADATA(     &
    CMNHNAME   = 'U_VAR',       &
    CSTDNAME   = '',            &
    CLONGNAME  = 'U_VAR',       &
    CUNITS     = 'm2 s-2',      &
    CDIR       = 'XY',          &
    CCOMMENT   = 'X_Y_Z_U_VAR', &
    NGRID      = 1,             &
    NTYPE      = TYPEREAL,      &
    NDIMS      = 3,             &
    LTIMEDEP   = .TRUE.         )
  CALL IO_Field_write(TPFILE,TZFIELD,ZFLX)
END IF
!
! Complete the U tendency
IF (.NOT. OFLAT) THEN
  CALL MXF_PHY(D, PDXX(:, :, :), ZMXF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PRHODJ(:, :, :) * ZFLX(:, :, :) / ZMXF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DXM_PHY(D, ZSHUGRADWK1_3D, ZDXM3D_WORK1)
CALL MZM_PHY(D, PDXX(:, :, :), ZMZM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK2_3D(:, :, :) = PRHODJ(:, :, :)*ZFLX(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL MZM_PHY(D, ZSHUGRADWK2_3D, ZMZM3D_WORK2)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = ZMZM3D_WORK2(:, :, :) * PINV_PDZZ(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL MXM_PHY(D, ZSHUGRADWK1_3D, ZMXM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PDZX(:, :, :) / ZMZM3D_WORK1(:, :, :) * ZMXM3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DZF_PHY(D, ZSHUGRADWK1_3D, ZDZF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
PRUS(:,:,:)=PRUS(:, :, :)                                            &
              -ZDXM3D_WORK1(:, :, :)                &
              +ZDZF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
ELSE
  CALL MXF_PHY(D, PDXX(:, :, :), ZMXF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PRHODJ(:, :, :) * ZFLX(:, :, :) / ZMXF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DXM_PHY(D, ZSHUGRADWK1_3D, ZDXM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
PRUS(:,:,:)=PRUS(:, :, :) -ZDXM3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
END IF
!
IF (KSPLT==1) THEN
  ! Contribution to the dynamic production of TKE:
   !$acc kernels async(2) present_cr(gx_u_m_pum,zwork)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZWORK(:,:,:)     = - ZFLX(:,:,:) * GX_U_M_PUM(:,:,:)
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
  !
  ! evaluate the dynamic production at w(IKB+1) in PDP(IKB)
  !
  !$acc kernels async(2) present_cr(zdu_dx,zwork)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
      ZWORK(:,:,IKB) = 0.5* ( -ZFLX(:,:,IKB)*ZDU_DX(:,:) + ZWORK(:,:,IKB+1) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
   !$acc end kernels
  !
  !$acc kernels async(2)
  PDP(:,:,:) = PDP(:,:,:) + ZWORK(:,:,:)
  !$acc end kernels
END IF
!
! Storage in the LES configuration
!
IF (TLES%LLES_CALL .AND. KSPLT==1) THEN
  CALL SECOND_MNH(ZTIME1)
  CALL LES_MEAN_SUBGRID( ZFLX, TLES%X_LES_SUBGRID_U2 ) 
  CALL LES_MEAN_SUBGRID( -ZWORK, TLES%X_LES_RES_ddxa_U_SBG_UaU , .TRUE.)
  CALL SECOND_MNH(ZTIME2)
  TLES%XTIME_LES = TLES%XTIME_LES + ZTIME2 - ZTIME1
END IF

!
!*      10.   < V'V'>
!             -------
!
!!! wait for the computation of ZWORK and PDP (that uses ZFLX)
!$acc wait(2)
!
! Computes the V variance
IF (.NOT. O2D) THEN
   !$acc kernels async(3) present_cr(gz_w_m_pwm,zflx)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZFLX(:,:,:)= (2./3.) * PTKEM(:,:,:)                                  &
           - XCMFS * PK(:,:,:) *( (4./3.) * GY_V_M_PVM(:,:,:)                        &
           -(2./3.) * ( GX_U_M_PUM(:,:,:)                      &
           +GZ_W_M_PWM(:,:,:)                ) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
   !$acc end kernels
  !! &  to be tested
  !!  + XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
  !
ELSE
   !$acc kernels async(3) present_cr(gz_w_m_pwm,zflx)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZFLX(:,:,:)= (2./3.) * PTKEM(:,:,:)                           &
           - XCMFS * PK(:,:,:) *(-(2./3.) * ( GX_U_M_PUM(:,:,:)        &
                                      +GZ_W_M_PWM(:,:,:)     ) )  
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
   !$acc end kernels
  !! &  to be tested
  !!  + XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
  !
END IF
!
!$acc kernels async(3)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKE+1) = ZFLX(:,:,IKE) 
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
! ! !!! wait for the computation of ZFLX to begin the update
! ! !$acc wait(3)
! ! !$acc update self(ZFLX(:,:,IKB+1:)) async(10)
!
!$acc kernels async(3) present_cr(zdv_dy,zflx)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZFLX(:,:,IKB)   = (2./3.) * PTKEM(:,:,IKB)                           &
        - XCMFS * PK(:,:,IKB) * 2. * ZDV_DY(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels

!!           & to be tested
!! + XCMFB * PLM(:,:,IKB:IKB) /SQRT(PTKEM(:,:,IKB:IKB)) *         &
!!   (-2./3.) * PTP(:,:,IKB:IKB)
!
! extrapolates this flux under the ground with the surface flux
!$acc kernels present_cr(ZFLX,ZDIRSINZW)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKB-1) =                                                            &
        PTAU11M(:,:) * PSINSLOPE(:,:)**2 * PDIRCOSZW(:,:)**2                 &         
  +2. * PTAU12M(:,:) * PCOSSLOPE(:,:)* PSINSLOPE(:,:) * PDIRCOSZW(:,:)       &
  +     PTAU22M(:,:) * PCOSSLOPE(:,:)**2                                     &
  +     PTAU33M(:,:) * PSINSLOPE(:,:)**2 * ZDIRSINZW(:,:)**2                 &
  -2. * PCDUEFF(:,:)*       (                                                &
      PUSLOPEM(:,:) * PSINSLOPE(:,:)**2 * ZDIRSINZW(:,:) * PDIRCOSZW(:,:)    &
    + PVSLOPEM(:,:) * PCOSSLOPE(:,:)    * PSINSLOPE(:,:) * ZDIRSINZW(:,:)    )
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
!$acc kernels async(3)
ZFLX(:,:,IKB-1) = 2. * ZFLX(:,:,IKB-1) -  ZFLX(:,:,IKB)
!$acc end kernels
!
!
! ! !!! wait for the computation of ZFLX(:,:,1:IKB) to begin the update
! ! !$acc update self(ZFLX(:,:,IKB+1:)) async(3)
! ! !
! ! !!! and wait for the update self(ZFLX(...)) to complete
! ! !$acc wait(10)
! ! !$acc wait(3)
!
!$acc wait(3)
#ifndef MNH_OPENACC
CALL UPDATE_HALO_ll(TZFIELDS_ll, IINFO_ll)
#else
CALL GET_HALO_D(ZFLX,HNAME='TURB_HOR_DYN_CORR::ZFLX')
#endif
!
IF ( TPFILE%LOPENED .AND. TURBN%LTURB_FLX ) THEN
  !$acc update self( ZFLX )
  ! stores <V V>  
  TZFIELD = TFIELDMETADATA(     &
    CMNHNAME   = 'V_VAR',       &
    CSTDNAME   = '',            &
    CLONGNAME  = 'V_VAR',       &
    CUNITS     = 'm2 s-2',      &
    CDIR       = 'XY',          &
    CCOMMENT   = 'X_Y_Z_V_VAR', &
    NGRID      = 1,             &
    NTYPE      = TYPEREAL,      &
    NDIMS      = 3,             &
    LTIMEDEP   = .TRUE.         )
  CALL IO_Field_write(TPFILE,TZFIELD,ZFLX)
END IF
!
!!! wait for the computation of PRUS (that uses temporary variables)
!$acc wait(1)
!
!
!
! Complete the V tendency
IF (.NOT. O2D) THEN
  IF (.NOT. OFLAT) THEN
    CALL MYF_PHY(D, PDYY(:, :, :), ZMYF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PRHODJ(:, :, :) * ZFLX(:, :, :) / ZMYF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DYM_PHY(D, ZSHUGRADWK1_3D, ZDYM3D_WORK1)
CALL MZM_PHY(D, PDYY(:, :, :), ZMZM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK2_3D(:, :, :) = PRHODJ(:, :, :)*ZFLX(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL MZM_PHY(D, ZSHUGRADWK2_3D, ZMZM3D_WORK2)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = ZMZM3D_WORK2(:, :, :) * PINV_PDZZ(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL MYM_PHY(D, ZSHUGRADWK1_3D, ZMYM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PDZY(:, :, :) / ZMZM3D_WORK1(:, :, :) *                      &
                ZMYM3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DZF_PHY(D, ZSHUGRADWK1_3D, ZDZF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
PRVS(:,:,:)=PRVS(:, :, :)                                          &
                -ZDYM3D_WORK1(:, :, :)              &
                +ZDZF3D_WORK1(:, :, :)  
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
ELSE
    CALL MYF_PHY(D, PDYY(:, :, :), ZMYF3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZSHUGRADWK1_3D(:, :, :) = PRHODJ(:, :, :) * ZFLX(:, :, :) / ZMYF3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
CALL DYM_PHY(D, ZSHUGRADWK1_3D, ZDYM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
PRVS(:,:,:)=PRVS(:, :, :) -ZDYM3D_WORK1(:, :, :)  
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
END IF
!
! Contribution to the dynamic production of TKE:
  IF (KSPLT==1) ZWORK(:,:,:)     = - ZFLX(:,:,:) * GY_V_M_PVM(:,:,:)
ELSE
  !$acc kernels async(2)
  !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  ZWORK(:,:,:)     = 0.
  !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
END IF
!
IF (KSPLT==1) THEN
  !
  ! evaluate the dynamic production at w(IKB+1) in PDP(IKB)
  !
   !$acc kernels async(2) present_cr(zdv_dy,zwork)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
      ZWORK(:,:,IKB) = 0.5* ( -ZFLX(:,:,IKB)*ZDV_DY(:,:) + ZWORK(:,:,IKB+1) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
   !$acc end kernels
  !
  !$acc kernels async(2)
  !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  PDP(:,:,:) = PDP(:,:,:) + ZWORK(:,:,:)
  !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
END IF
!
! Storage in the LES configuration
!
IF (TLES%LLES_CALL .AND. KSPLT==1) THEN
  CALL SECOND_MNH(ZTIME1)
  CALL LES_MEAN_SUBGRID( ZFLX, TLES%X_LES_SUBGRID_V2 ) 
  CALL LES_MEAN_SUBGRID( -ZWORK, TLES%X_LES_RES_ddxa_V_SBG_UaV , .TRUE.)
  CALL SECOND_MNH(ZTIME2)
  TLES%XTIME_LES = TLES%XTIME_LES + ZTIME2 - ZTIME1
END IF
!
!*      11.   < W'W'>
!             -------
!
! Computes the W variance
IF (.NOT. O2D) THEN
   !$acc kernels async(2) present_cr(gy_v_m_pvm,zflx)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZFLX(:,:,:) = (2./3.) * PTKEM(:,:,:)                                  &
           - XCMFS * PK(:,:,:) *( (4./3.) * GZ_W_M_PWM(:,:,:)                        &
           -(2./3.) * ( GX_U_M_PUM(:,:,:)                      &
           +GY_V_M_PVM(:,:,:)                ) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
  !!  &  to be tested
  !!    -2.* XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
ELSE
   !$acc kernels async(2) present_cr(gx_u_m_pum,zflx)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZFLX(:,:,:)= (2./3.) * PTKEM(:,:,:)                           &
           - XCMFS * PK(:,:,:) *( (4./3.) * GZ_W_M_PWM(:,:,:)          &
           -(2./3.) * ( GX_U_M_PUM(:,:,:)           ) ) 
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
   !$acc end kernels
  !!  &  to be tested
  !!    -2.* XCMFB *  PLM / SQRT(PTKEM) * (-2./3.) * PTP 
END IF
!
!$acc kernels async(2)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKE+1)= ZFLX(:,:,IKE)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!!! wait for the computation of ZWORK, PDP and ZFLX
!$acc wait(2)
!
!
!$acc kernels async(2) present_cr(zdw_dz,zflx)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
   ZFLX(:,:,IKB)   = (2./3.) * PTKEM(:,:,IKB)                           &
        - XCMFS * PK(:,:,IKB) * 2. * ZDW_DZ(:,:)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)

!$acc end kernels
!

!             &  to be tested
!   - 2.* XCMFB * PLM(:,:,IKB:IKB) /SQRT(PTKEM(:,:,IKB:IKB)) *             &
!  (-2./3.) * PTP(:,:,IKB:IKB)
! extrapolates this flux under the ground with the surface flux
!$acc kernels async(3) present_cr(ZFLX)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKB-1) =                                                     &
        PTAU11M(:,:) * ZDIRSINZW(:,:)**2                                &
  +     PTAU33M(:,:) * PDIRCOSZW(:,:)**2                                &
  +2. * PCDUEFF(:,:)* PUSLOPEM(:,:)  * ZDIRSINZW(:,:) * PDIRCOSZW(:,:) 
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)        
!$acc end kernels
! 
!
!!! wait for the computation of ZFLX(:,:,IKB-1) and ZFLX(:,:,IKB)
!$acc wait(2) async(3)
!
!$acc kernels async(3)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
ZFLX(:,:,IKB-1) = 2. * ZFLX(:,:,IKB-1) - ZFLX(:,:,IKB)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
!$acc end kernels
!
IF ( TPFILE%LOPENED .AND. TURBN%LTURB_FLX ) THEN
  !$acc wait(3)
  !$acc update self(ZFLX)
  ! stores <W W>  
  TZFIELD = TFIELDMETADATA(     &
    CMNHNAME   = 'W_VAR',       &
    CSTDNAME   = '',            &
    CLONGNAME  = 'W_VAR',       &
    CUNITS     = 'm2 s-2',      &
    CDIR       = 'XY',          &
    CCOMMENT   = 'X_Y_Z_W_VAR', &
    NGRID      = 1,             &
    NTYPE      = TYPEREAL,      &
    NDIMS      = 3,             &
    LTIMEDEP   = .TRUE.         )
  CALL IO_Field_write(TPFILE,TZFIELD,ZFLX)
END IF
!
!
!!! wait for the computation of PRVS (that uses temporary variables)
!$acc wait(1)
!

!
! Complete the W tendency
!
!PRWS(:,:,:)=PRWS(:,:,:) - DZM( PRHODJ*ZFLX/MZF(PDZZ) )
!$acc kernels async(2)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
ZDFDDWDZ(:,:,:)    = - XCMFS * PK(:,:,:) * (4./3.)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!$acc kernels async(2)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKB)
ZDFDDWDZ(:,:,1:IKB) = 0.
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKB)
!$acc end kernels
!
!!! wait for the computation of ZFLX(:,:,IKB-1) and ZDFDDWDZ
!$acc wait(3) async(2)
!$acc wait(2)
!
CALL TRIDIAG_W(PWM,ZFLX,ZDFDDWDZ,PTSTEP,ZMZF_DZZ,PRHODJ,ZWP)
!
CALL MZM_PHY(D, PRHODJ(:,:,:), ZMZM3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
PRWS(:, :, :) = PRWS(:,:,:) + ZMZM3D_WORK1(:, :, :)*(ZWP(:,:,:)-PWM(:,:,:))/PTSTEP
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
!
!* recomputes flux using guess of W
!
CALL GZ_W_M_PHY(D, ZWP(:, :, :),PDZZ(:, :, :), ZGZ_W_M3D_WORK1)
!$acc kernels
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
GZ_W_M_ZWP(:, :, :) = ZGZ_W_M3D_WORK1(:, :, :)
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
!$acc end kernels
!
!$acc kernels async(2) present_cr(gz_w_m_pwm,zflx)
!$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=IKB+1:IKT)
   ZFLX(:,:,:)=ZFLX(:,:,:) &
        - XCMFS * PK(:,:,:) * (4./3.) * (GZ_W_M_ZWP(:,:,:) - GZ_W_M_PWM(:,:,:))
!$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=IKB+1:IKT)
!$acc end kernels
!
IF (KSPLT==1) THEN
   !Contribution to the dynamic production of TKE:
   !$acc kernels async(2) present_cr(gz_w_m_zwp,zwork)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
      ZWORK(:,:,:) = - ZFLX(:,:,:) * GZ_W_M_ZWP(:,:,:)
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)   
   !$acc end kernels
  !
  ! evaluate the dynamic production at w(IKB+1) in PDP(IKB)
  !
   !$acc kernels async(2) present_cr(zdw_dz,zwork)
   !$mnh_expand_array(JI=1:IIT,JJ=1:IJT)
      ZWORK(:,:,IKB) = 0.5* ( -ZFLX(:,:,IKB)*ZDW_DZ(:,:) + ZWORK(:,:,IKB+1) )
   !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT)
   !$acc end kernels
  !
  !$acc kernels async(2)
  !$mnh_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  PDP(:,:,:) = PDP(:,:,:) + ZWORK(:,:,:)
  !$mnh_end_expand_array(JI=1:IIT,JJ=1:IJT,JK=1:IKT)
  !$acc end kernels
END IF
!
! Storage in the LES configuration
!
!
IF (TLES%LLES_CALL .AND. KSPLT==1) THEN
  CALL SECOND_MNH(ZTIME1)
  CALL LES_MEAN_SUBGRID( ZFLX, TLES%X_LES_SUBGRID_W2 ) 
  CALL LES_MEAN_SUBGRID( -ZWORK, TLES%X_LES_RES_ddxa_W_SBG_UaW , .TRUE.)
  CALL LES_MEAN_SUBGRID( GZ_M_M(PTHLM,PDZZ)*ZFLX, TLES%X_LES_RES_ddxa_Thl_SBG_UaW , .TRUE.)
  CALL GZ_M_W_PHY(D, PTHLM(:, :, :),PDZZ(:, :, :), ZGZ_M_W3D_WORK1)
CALL MZF_PHY(D, ZGZ_M_W3D_WORK1, ZMZF3D_WORK1)
CALL LES_MEAN_SUBGRID(ZFLX(:, :, :)*ZMZF3D_WORK1(:, :, :),TLES%X_LES_RES_ddz_Thl_SBG_W2)  
IF (KRR>=1) THEN
    CALL LES_MEAN_SUBGRID( GZ_M_M(PRM(:,:,:,1),PDZZ)*ZFLX, &
                           TLES%X_LES_RES_ddxa_Rt_SBG_UaW , .TRUE.)
    CALL GZ_M_W_PHY(D, PRM(:,:,:,1),PDZZ(:, :, :), ZGZ_M_W3D_WORK1)
CALL MZF_PHY(D, ZGZ_M_W3D_WORK1, ZMZF3D_WORK1)
CALL LES_MEAN_SUBGRID(ZFLX(:, :, :)*ZMZF3D_WORK1(:, :, :), &
                           TLES%X_LES_RES_ddz_Rt_SBG_W2)  
END IF
  DO JSV=1,KSV
    CALL LES_MEAN_SUBGRID( GZ_M_M(PSVM(:,:,:,JSV),PDZZ)*ZFLX, &
                           TLES%X_LES_RES_ddxa_Sv_SBG_UaW(:,:,:,JSV) , .TRUE.)
    CALL GZ_M_W_PHY(D, PSVM(:,:,:,JSV),PDZZ(:, :, :), ZGZ_M_W3D_WORK1)
CALL MZF_PHY(D, ZGZ_M_W3D_WORK1, ZMZF3D_WORK1)
CALL LES_MEAN_SUBGRID(ZFLX(:, :, :)*ZMZF3D_WORK1(:, :, :), &
                           TLES%X_LES_RES_ddz_Sv_SBG_W2(:,:,:,JSV))  
END DO
  CALL SECOND_MNH(ZTIME2)
  TLES%XTIME_LES = TLES%XTIME_LES + ZTIME2 - ZTIME1
END IF
!
CALL CLEANLIST_ll(TZFIELDS_ll)
!
!
END SUBROUTINE TURB_HOR_DYN_CORR
END MODULE MODE_TURB_HOR_DYN_CORR
