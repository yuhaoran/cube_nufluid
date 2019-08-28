!Program to compute neutrino initial conditions given delta_c at z=z_i_nu
program neutrino_ic
  use omp_lib
  use parameters
  use variables
  use pencil_fft
  use hydrodf
  implicit none
  save

  !Free streaming scale for v=1km/s: kfs=sqrt( 1.5*omega_m*a*H0^2/v^2)
  real, parameter :: kfs1=sqrt(1.5*omega_m/(1.+z_i_nu))*100.
  
  ! Array to store cdm fields to prevent multiple reads
  real :: r3_cpy(ng,ng,ng)

  ! Useful variables
  integer :: ig,jg,kg,n,d
  real :: kx,ky,kz,kr,kp,kfs,vneu,ll,tf
  character(len=1), dimension(3), parameter :: xyz = (/'x','y','z'/)

  call omp_set_num_threads(ncore)
  call geometry
  call create_penfft_plan

  if (head) write(*,*) 'Program: neutrino_ic'

  !Setup neutrino field with homogeneous ic
  if (head) hg_verb=2
  do nu=1,Nneu
     call neu(nu)%setup(real(5./3.,kind=h_fpp), real(Mneu(nu),kind=h_fpp),.true.)
  end do

  !First compute density perturbations

  ! Read in CDM density field
  if (head) write(*,*) 'Reading CDM density field from file: '//output_dir()//'delta_L'//output_suffix()
  open(11,file=output_dir()//'delta_L'//output_suffix(),access='stream',status='old')
  read(11) r3
  close(11)
  r3_cpy=r3

  ! Compute density fields

  !! Loop over neutrinos
  do nu=1,Nneu

     !!! Loop over momenta
     do n=1,dfld_n_hydro

        !4 Compute free streaming scale
        vneu=dfld_GL_v(n)/dfld_beta_eV*dfld_sol/Mneu(nu) !v=u*k*T*c/m
        write(*,*) 'velocity: ',vneu,'km/s'
        kfs=kfs1/vneu
        write(*,*) 'kfs=',kfs,'h/Mpc'
     
        !4 Transform r3 into Fourier space, stored as cxyz
        call pencil_fft_forward

        !4 Loop over modes
        do k=1,npen
           do j=1,nf
              do i=1,nyquest+1
                 !5 ig,jg,kg are the global coordinates, labeled from the first node
                 kg=(nn*(icz-1)+icy-1)*npen+k
                 jg=(icx-1)*nf+j
                 ig=i
                 !5 kx,ky,kz are Fourier frequencies
                 kz=mod(kg+nyquest-1,nf_global)-nyquest
                 ky=mod(jg+nyquest-1,nf_global)-nyquest
                 kx=ig-1
                 !5 kr is the k we are using
                 kr=sqrt(kx**2+ky**2+kz**2)
                 !5 compute physical k
                 kp=kr*2.*pi/box
                 ll=kp/kfs
                 !5 compute cdm->fluid tranfer function
                 tf=1./(1.+ll+ll**2)
                 !5 apply
                 cxyz(i,j,k)=cxyz(i,j,k)*tf
              enddo
           enddo
        enddo
     
        sync all

        !4 Transforms cxyz into real space, stored as r3
        call pencil_fft_backward

        !4 Store density field in neu
        call neu(nu)%n_hydro(n)%set_fld(1+r3,1) !rho=1+delta=1+r3

        !4 Store energy field as well
        neu(nu)%n_hydro(n)%fld(5,:,:,:)=neu(nu)%n_hydro(n)%fld(1,:,:,:)*neu(nu)%n_hydro(n)%cs2/(neu(nu)%n_hydro(n)%g-1.)

        !4 Reset r3
        r3=r3_cpy
        
     end do !n

  end do !nu

  ! Now compute velocity perturbations
  do d=1,3

     ! Read in CDM velocity field
     if (head) write(*,*) 'Reading CDM '//xyz(d)//'velocity field from file: '//output_dir()//'v_'//xyz(d)//'_L'//output_suffix()
     open(11,file=output_dir()//'v_'//xyz(d)//'_L'//output_suffix(),access='stream',status='old')
     read(11) r3
     close(11)
     r3_cpy=r3
  
     ! Compute velocity fields

     !! Loop over neutrinos
     do nu=1,Nneu

        !!! Loop over momenta
        do n=1,dfld_n_hydro

           !4 Compute free streaming scale
           vneu=dfld_GL_v(n)/dfld_beta_eV*dfld_sol/Mneu(nu) !v=u*k*T*c/m
           kfs=kfs1/vneu
     
           !4 Transform r3 into Fourier space, stored as cxyz
           call pencil_fft_forward

           !4 Loop over modes
           do k=1,npen
              do j=1,nf
                 do i=1,nyquest+1
                    !5 ig,jg,kg are the global coordinates, labeled from the first node
                    kg=(nn*(icz-1)+icy-1)*npen+k
                    jg=(icx-1)*nf+j
                    ig=i
                    !5 kx,ky,kz are Fourier frequencies
                    kz=mod(kg+nyquest-1,nf_global)-nyquest
                    ky=mod(jg+nyquest-1,nf_global)-nyquest
                    kx=ig-1
                    !5 kr is the k we are using
                    kr=sqrt(kx**2+ky**2+kz**2)
                    !5 compute physical k
                    kp=kr*2.*pi/box
                    ll=kp/kfs
                    !5 compute cdm->fluid tranfer function
                    tf=(1.+1.5*ll+2.*ll**2)/(1.+ll+ll**2)**2
                    !5 apply
                    cxyz(i,j,k)=cxyz(i,j,k)*tf
                 enddo
              enddo
           enddo
     
           sync all

           !4 Transforms cxyz into real space, stored as r3
           call pencil_fft_backward

           !4 Store velocity field in neu
           call neu(nu)%n_hydro(n)%set_fld(r3,1+d)

           !4 Convert velocity field to momentum field
           neu(nu)%n_hydro(n)%fld(1+d,:,:,:)=neu(nu)%n_hydro(n)%fld(1,:,:,:)*neu(nu)%n_hydro(n)%fld(1+d,:,:,:)

           !4 Reset r3
           r3=r3_cpy

        !Write out some information
        if (d.eq.3) call hg_hydro_properties(neu(nu)%n_hydro(n))
        
        end do !n

     end do !nu

  end do !d

  do nu=1,Nneu
     write(astr,'(I10)') nu
     if (head) write(*,*) 'Checkpointing to file: '//output_dir()//'neu'//trim(adjustl(astr))//output_suffix()
     call neu(nu)%checkpoint(output_dir()//'neu'//trim(adjustl(astr))//output_suffix())
  end do

end program neutrino_ic
