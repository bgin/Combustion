/*
 * RNS encapsulation for SDCLib.
 *
 * Notes:
 *   - State/solution encaps are created with grow/ghost cells.
 *   - Function evaluation encaps are created without grow/ghost cells.
 *   - Integral encaps are created without grow/ghost cells.
 *
 * XXX: Note that the FEVAL encapsulations have flux registers, and
 * since we're using the IMEX sweeper, both the "explicit" feval and
 * "implicit" feval will have flux registers, but this isn't
 * necessary.  Matt should clean this up sometime.
 */

#include <MultiFab.H>
#include <SDCAmr.H>
#include <StateDescriptor.H>
#include <AmrLevel.H>

#include <cassert>

BEGIN_EXTERN_C

#ifdef USE_FUTURE
void interp_bnd(void *Q, void *Q0, void *Q2, void *Q4,
		void *F0, void *F2, void *F4, sdc_dtype dt, int m)
{
    MultiFab& U  = *((RNSEncap*)Q )->U;
    MultiFab& U0 = *((RNSEncap*)Q0)->U;
    MultiFab& U2 = *((RNSEncap*)Q2)->U;
    MultiFab& U4 = *((RNSEncap*)Q4)->U;
    MultiFab& f0 = *((RNSEncap*)F0)->U;
    MultiFab& f2 = *((RNSEncap*)F2)->U;
    MultiFab& f4 = *((RNSEncap*)F4)->U;

    int nc = U.nComp();
    int ng = U.nGrow();

    Real c0, c2, c4;
    if (m == 1) {
	c0 = ( 8./12.)*(0.25*dt);
	c2 = ( 5./12.)*(0.25*dt);
	c4 = (-1./12.)*(0.25*dt);
    }
    else if (m == 2) {
	c0 = ( 5./12.)*(0.5*dt);
	c2 = ( 8./12.)*(0.5*dt);
	c4 = (-1./12.)*(0.5*dt);
    }
    else if (m == 3) {
	c0 = (1./4.)*(0.75*dt);
	c2 = (3./4.)*(0.75*dt);
	c4 = 0.0;
    }
    else if (m == 4) {
	c0 = (1./6.)*dt;
	c2 = (4./6.)*dt;
	c4 = (1./6.)*dt;
    }
    else {
	std::cout << " m = " << m << std::endl;
	BoxLib::Abort("interp_bnd: wrong m");
    }

    for (MFIter mfi(U); mfi.isValid(); ++mfi) {
	int i = mfi.index();
	const Box& gbox = U[i].box();
	const Box& vbox = mfi.validbox();

	FArrayBox Utmp(gbox, nc);
	Utmp.copy(U0[i]);
	Utmp.saxpy(c0, f0[i]);
	Utmp.saxpy(c2, f2[i]);
	Utmp.saxpy(c4, f4[i]);

	// only want to overwrite boundaries of U
	Utmp.saxpy(-1.0, U[i]);
	Utmp.setVal(0.0, vbox, 0, nc);
	U[i] += Utmp;
    }
}
#endif

void mf_encap_setval(void *Qptr, sdc_dtype val, const int flags);


void *mf_encap_create(int type, void *encap_ctx)
{
  RNSEncapCtx* ctx   = (RNSEncapCtx*) encap_ctx;
  RNSEncap*    encap = new RNSEncap;

  encap->rns       = ctx->rns;
  encap->type      = type;
  encap->fine_flux = 0;
  encap->crse_flux = 0;

  switch (type) {
  case SDC_SOLUTION:
  case SDC_WORK:
    encap->U = new MultiFab(*ctx->ba, ctx->ncomp, ctx->ngrow);
    break;
  case SDC_FEVAL:
  case SDC_INTEGRAL:
  case SDC_TAU:
    encap->U = new MultiFab(*ctx->ba, ctx->ncomp, 0);
    if (ctx->level > 0)
      encap->fine_flux = new FluxRegister(*ctx->ba, ctx->crse_ratio, ctx->level, ctx->ncomp);
    if (ctx->level < ctx->finest) {
      SDCAmr&   amr  = *encap->rns->getSDCAmr();
      AmrLevel& rnsF = amr.getLevel(ctx->level+1);
      encap->crse_flux = new FluxRegister(rnsF.boxArray(), amr.refRatio(ctx->level), rnsF.Level(), ctx->ncomp);
    }
    break;
  }

  mf_encap_setval(encap, 0.0, SDC_ENCAP_ALL);
  return encap;
}

void mf_encap_destroy(void *Qptr)
{
  RNSEncap* Q = (RNSEncap*) Qptr;
  delete Q->U;
  if (Q->fine_flux != NULL) delete Q->fine_flux;
  if (Q->crse_flux != NULL) delete Q->crse_flux;
  delete Q;
}

void mf_encap_setval_flux(FluxRegister& dst, sdc_dtype val)
{
  for (OrientationIter face; face; ++face)
    for (FabSetIter bfsi(dst[face()]); bfsi.isValid(); ++bfsi)
      dst[face()][bfsi].setVal(val);
}

void mf_encap_setval(void *Qptr, sdc_dtype val, const int flags)
{
  RNSEncap& Q = *((RNSEncap*) Qptr);
  MultiFab& U = *Q.U;

  if ((flags & SDC_ENCAP_INTERIOR) && (flags & SDC_ENCAP_GHOST))
    U.setVal(val, U.nGrow());
  else
    U.setVal(val, 0);

  if (Q.fine_flux) mf_encap_setval_flux(*Q.fine_flux, val);
  if (Q.crse_flux) mf_encap_setval_flux(*Q.crse_flux, val);
}

void mf_encap_copy_flux(FluxRegister& dst, FluxRegister& src)
{
  for (OrientationIter face; face; ++face)
    for (FabSetIter bfsi(dst[face()]); bfsi.isValid(); ++bfsi)
      dst[face()][bfsi].copy(src[face()][bfsi]);
}

void mf_encap_copy(void *dstp, const void *srcp, int flags)
{
  RNSEncap& Qdst = *((RNSEncap*) dstp);
  RNSEncap& Qsrc = *((RNSEncap*) srcp);
  MultiFab& Udst = *Qdst.U;
  MultiFab& Usrc = *Qsrc.U;

  if ((flags & SDC_ENCAP_INTERIOR) && (flags & SDC_ENCAP_GHOST)) {
    int ngsrc = Usrc.nGrow();
    int ngdst = Udst.nGrow();
    int nghost = (ngdst < ngsrc) ? ngdst : ngsrc;
    MultiFab::Copy(Udst, Usrc, 0, 0, Usrc.nComp(), nghost);
  } else {
    MultiFab::Copy(Udst, Usrc, 0, 0, Usrc.nComp(), 0);
  }

  if (Qdst.fine_flux && Qsrc.fine_flux) mf_encap_copy_flux(*Qdst.fine_flux, *Qsrc.fine_flux);
  if (Qdst.crse_flux && Qsrc.crse_flux) mf_encap_copy_flux(*Qdst.crse_flux, *Qsrc.crse_flux);

#ifndef NDEBUG
  BL_ASSERT(Usrc.contains_nan() == false);
  BL_ASSERT(Udst.contains_nan() == false);
#endif
}

void mf_encap_saxpy_flux(FluxRegister& y, sdc_dtype a, FluxRegister& x)
{
  for (OrientationIter face; face; ++face)
    for (FabSetIter bfsi(y[face()]); bfsi.isValid(); ++bfsi)
      y[face()][bfsi].saxpy(a, x[face()][bfsi]);
}

void mf_encap_saxpy(void *yp, sdc_dtype a, void *xp, int flags)
{
  RNSEncap& Qy = *((RNSEncap*) yp);
  RNSEncap& Qx = *((RNSEncap*) xp);
  MultiFab& Uy = *Qy.U;
  MultiFab& Ux = *Qx.U;

  BL_ASSERT(Uy.boxArray() == Ux.boxArray());

// #ifdef _OPENMP
// #pragma omp parallel for
// #endif
  for (MFIter mfi(Uy); mfi.isValid(); ++mfi)
    Uy[mfi].saxpy(a, Ux[mfi]);

  if ((Qy.type==SDC_TAU) && (Qx.fine_flux!=NULL)) mf_encap_saxpy_flux(*Qy.fine_flux, a, *Qx.fine_flux);
  if ((Qy.type==SDC_TAU) && (Qx.crse_flux!=NULL)) mf_encap_saxpy_flux(*Qy.crse_flux, a, *Qx.crse_flux);
}

END_EXTERN_C


sdc_encap* SDCAmr::build_encap(int lev)
{
  const DescriptorList& dl = getLevel(lev).get_desc_lst();
  assert(dl.size() == 1);       // valid for RNS

  RNSEncapCtx* ctx = new RNSEncapCtx;
  ctx->level  = lev;
  ctx->ba     = &boxArray(lev);
  ctx->rns    = dynamic_cast<RNS*>(&getLevel(lev));
  ctx->finest = finest_level;
  ctx->ncomp  = dl[0].nComp();
  ctx->ngrow  = dl[0].nExtra();
  if (lev > 0)
    ctx->crse_ratio = refRatio(lev-1);

  sdc_encap* encap = new sdc_encap;
  encap->create  = mf_encap_create;
  encap->destroy = mf_encap_destroy;
  encap->setval  = mf_encap_setval;
  encap->copy    = mf_encap_copy;
  encap->saxpy   = mf_encap_saxpy;
  encap->ctx     = ctx;

  return encap;
}

void SDCAmr::destroy_mlsdc()
{
  for (unsigned int lev=0; lev<=max_level; lev++) {
    if (sweepers[lev] != NULL) {
      sweepers[lev]->destroy(sweepers[lev]);
      sweepers[lev] = NULL;
      delete (RNSEncapCtx*) encaps[lev]->ctx;
      delete encaps[lev];
    }
  }
}
