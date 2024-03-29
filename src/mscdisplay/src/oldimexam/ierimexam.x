# Copyright(c) 1986 Association of Universities for Research in Astronomy Inc.

include	<error.h>
include	<imhdr.h>
include	<gset.h>
include	<math.h>
include	<math/gsurfit.h>
include	<math/nlfit.h>
include	"imexam.h"
include "../mosim.h"


# IE_RIMEXAM -- Radial profile plot and photometry parameters.
# If no GIO pointer is given then only the photometry parameters are printed.
# First find the center using the marginal distributions.  Then subtract
# a fit to the background.  Compute the moments within the aperture and
# fit a gaussian of fixed center and zero background.  Make the plot
# and print the photometry values.

procedure ie_rimexam (gp, mode, ie, x, y)

pointer	gp
pointer	ie
int	mode
real	x, y

bool	center, background, medsky, fitplot, clgpsetb()
real	radius, buffer, width, magzero, rplot, clgpsetr()
int	xorder, yorder, clgpseti()

int	i, j, ns, no, np, nx, ny, npts, x1, x2, y1, y2, plist[2]
real	bkg, xcntr, ycntr, mag, e, pa, zcntr, wxcntr, wycntr
real	params[2], dparams[2]
real	fwhm, dbkg, dpeak, dfwhm, efwhm
pointer	sp, title, coords, im, data, pp, ws, xs, ys, zs, gs, ptr, nl
double	sumo, sums, sumxx, sumyy, sumxy
real	r, r1, r2, r3, dx, dy, gseval(), amedr()
pointer	clopset(), ie_gimage(), ie_gdata(), locpr()
extern	ie_gauss(), ie_dgauss()
errchk	stf_measure, nlinit, nlfit

data	plist/1,2/
string	label1 "#   \
COL    LINE                             ---- FULL WIDTH AT HALF-MAXIMUM ---\n"
string	label2 "#   \
MAG    FLUX     SKY    PEAK ELLIP    PA   MOMENT ENCLOSED GAUSSIAN   DIRECT\n"

begin
	iferr (im = ie_gimage (ie, NO)) {
	    call erract (EA_WARN)
	    return
	}

	# Open parameter set.
	if (gp != NULL) {
	    if (IE_PP(ie) != NULL)
		call clcpset (IE_PP(ie))
	}
	pp = clopset ("rimexam2")

	center = clgpsetb (pp, "center")
	background = clgpsetb (pp, "background")
	radius = clgpsetr (pp, "radius")
	if (background) {
	    buffer = clgpsetr (pp, "buffer")
	    width = clgpsetr (pp, "width")
	    xorder = clgpseti (pp, "xorder")
	    yorder = clgpseti (pp, "yorder")
	    medsky = (xorder <= 0 || yorder <= 0)
	} else {
	    buffer = 0.
	    width = 0.
	}
	magzero = clgpsetr (pp, "magzero")
	rplot = clgpsetr (pp, "rplot")
	fitplot = clgpsetb (pp, "fitplot")

	# If the initial center is INDEF then use the previous value.
	if (gp != NULL) {
	    if (!IS_INDEF(x))
	        IE_X1(ie) = x
	    if (!IS_INDEF(y))
	        IE_Y1(ie) = y

	    xcntr = IE_X1(ie)
	    ycntr = IE_Y1(ie)
	} else {
	    xcntr = x
	    ycntr = y
	}

	# Center
	if (center)
	    iferr (call ie_center (im, radius, xcntr, ycntr)) {
		call erract (EA_WARN)
		return
	    }

	# Do the enclosed flux and direct FWHM measurments using the
	# PSFMEASURE routines.

	call stf_measure (im, xcntr, ycntr, 0.5, radius, 1, buffer, width,
	    INDEF, NULL, NULL, dbkg, dpeak, dfwhm, efwhm)

	# Get data including a buffer and background annulus.
	r = max (rplot, radius + buffer + width)
	x1 = xcntr - r
	x2 = xcntr + r
	y1 = ycntr - r
	y2 = ycntr + r
	iferr (data = ie_gdata (im, x1, x2, y1, y2)) {
	    call erract (EA_WARN)
	    return
	}

	nx = x2 - x1 + 1
	ny = y2 - y1 + 1
	npts = nx * ny

	call smark (sp)
	call salloc (title, IE_SZTITLE, TY_CHAR)
	call salloc (coords, IE_SZTITLE, TY_CHAR)
	call salloc (xs, npts, TY_REAL)
	call salloc (ys, npts, TY_REAL)
	call salloc (ws, npts, TY_REAL)

	# Extract the background data if background subtracting.
	ns = 0
	if (background && width > 0.) {
	    call salloc (zs, npts, TY_REAL)

	    r1 = radius ** 2
	    r2 = (radius + buffer) ** 2
	    r3 = (radius + buffer + width) ** 2

	    ptr = data
	    do j = y1, y2 {
	        dy = (ycntr - j) ** 2
	        do i = x1, x2 {
		    r = (xcntr - i) ** 2 + dy
		    if (r <= r1)
		        ;
		    else if (r >= r2 && r <= r3) {
		        Memr[xs+ns] = i
		        Memr[ys+ns] = j
		        Memr[zs+ns] = Memr[ptr]
		        ns = ns + 1
		    }
		    ptr = ptr + 1
	        }
	    }
	}
 
	# Accumulate the various sums for the moments and the gaussian fit.
	no = 0
	np = 0
	zcntr = 0.
	sumo = 0.; sums = 0.; sumxx = 0.; sumyy = 0.; sumxy = 0.
	ptr = data
	gs = NULL

	if (ns > 0) {		# Background subtraction

	    # If background points are defined fit a surface and subtract
	    # the fitted background from within the object aperture. 

	    if (medsky)
		bkg = amedr (Memr[zs], ns)
	    else {
		repeat {
		    call gsinit (gs, GS_POLYNOMIAL, xorder, yorder, YES,
			real (x1), real (x2), real (y1), real (y2))
		    call gsfit (gs, Memr[xs], Memr[ys], Memr[zs], Memr[ws], ns,
			WTS_UNIFORM, i)
		    if (i == OK)
			break
		    xorder = max (1, xorder - 1)
		    yorder = max (1, yorder - 1)
		    call gsfree (gs)
		}
		bkg = gseval (gs, real(x1), real(y1))
	    }

	    do j = y1, y2 {
	        dy = j - ycntr
	        do i = x1, x2 {
		    dx = i - xcntr
		    r = sqrt (dx ** 2 + dy ** 2)
		    r3 = max (0., min (5., 2 * r / dfwhm - 1.))

		    if (medsky)
			r2 = bkg
		    else {
			r2 = gseval (gs, real(i), real(j))
			bkg = min (bkg, r2)
		    }
		    r1 = Memr[ptr] - r2

		    if (r <= radius) {
			sumo = sumo + r1
			sums = sums + r2
			sumxx = sumxx + dx * dx * r1
			sumyy = sumyy + dy * dy * r1
			sumxy = sumxy + dx * dy * r1
			zcntr = max (r1, zcntr)
			if (r <= rplot) {
			    Memr[xs+no] = r
			    Memr[ys+no] = r1
			    Memr[ws+no] = exp (-r3**2) / max (.1, r**2)
			    no = no + 1
			} else {
			    np = np + 1
			    Memr[xs+npts-np] = r
			    Memr[ys+npts-np] = r1
			    Memr[ws+npts-np] = exp (-r3**2) / max (.1, r**2)
			}
		    } else if (r <= rplot) {
		        np = np + 1
		        Memr[xs+npts-np] = r
		        Memr[ys+npts-np] = r1
		    }
		    ptr = ptr + 1
		}
	    }

	    if (gs != NULL)
	        call gsfree (gs)

	} else {		# No background subtraction
	    bkg = 0.
	    do j = y1, y2 {
	        dy = j - ycntr
	        do i = x1, x2 {
		    dx = i - xcntr
		    r = sqrt (dx ** 2 + dy ** 2)
		    r3 = max (0., min (5., 2 * r / dfwhm - 1.))
		    r1 = Memr[ptr]

		    if (r <= radius) {
			sumo = sumo + r1
			sumxx = sumxx + dx * dx * r1
			sumyy = sumyy + dy * dy * r1
			sumxy = sumxy + dx * dy * r1
			zcntr = max (r1, zcntr)
			if (r <= rplot) {
			    Memr[xs+no] = r
			    Memr[ys+no] = r1
			    Memr[ws+no] = exp (-r3**2) / max (.1, r**2)
			    no = no + 1
			} else {
			    np = np + 1
			    Memr[xs+npts-np] = r
			    Memr[ys+npts-np] = r1
			    Memr[ws+npts-np] = exp (-r3**2) / max (.1, r**2)
			}
		    } else if (r <= rplot) {
		        np = np + 1
		        Memr[xs+npts-np] = r
		        Memr[ys+npts-np] = r1
		    }
		    ptr = ptr + 1
		}
	    }
	}
	if (np > 0) {
	    call amovr (Memr[xs+npts-np], Memr[xs+no], np)
	    call amovr (Memr[ys+npts-np], Memr[ys+no], np)
	    call amovr (Memr[ws+npts-np], Memr[ws+no], np)
	}
	if (rplot <= radius) {
	    no = no + np
	    np = no - np 
	} else
	    np = no + np
	    

	# Compute the photometry and gaussian fit parameters.

	mag = INDEF
	r = INDEF
	e = INDEF
	pa = INDEF
	if (sumo > 0.) {
	    mag = magzero - 2.5 * log10 (sumo)
	    r2 = sumxx + sumyy
	    if (r2 > 0.) {
	        r = 2 * sqrt (log (2.) * r2 / sumo)
	        r1 =(sumxx-sumyy)**2+(2*sumxy)**2
		if (r1 > 0.)
		    e = sqrt (r1) / r2
	        else
		    e = 0.
	    }
	    if (e < 0.01)
		e = 0.
	    else
		pa = RADTODEG (0.5 * atan2 (2*sumxy, sumxx-sumyy))
	}

	params[1] = zcntr
	if (IS_INDEFR(r))
	    params[2] = 0.25 * radius
	else
	    params[2] = r**2 / (8 * log(2.))
	call nlinitr (nl, locpr (ie_gauss), locpr (ie_dgauss), 
	    params, dparams, 2, plist, 2, .001, 100)
	call nlfitr (nl, Memr[xs], Memr[ys], Memr[ws], no, 1, WTS_USER, i)
	if (i == SINGULAR || i == NO_DEG_FREEDOM) {
	    call eprintf ("WARNING: Gaussian fit did not converge\n")
	    call tsleep (5)
	    zcntr = INDEF
	    fwhm = INDEF
	} else {
	    call nlpgetr (nl, params, i)
	    if (params[2] < 0.) {
		zcntr = INDEF
		fwhm = INDEF
	    } else {
		zcntr = params[1]
		fwhm = sqrt (8 * log (2.) * params[2])
	    }
	}

	call ie_mwctran (ie, xcntr, ycntr, wxcntr, wycntr)
	if (xcntr == wxcntr && ycntr == wycntr)
	    call strcpy ("%.2f %.2f", Memc[title], IE_SZTITLE)
	else {
	    call sprintf (Memc[title], IE_SZTITLE, "%s %s")
		if (IE_XFORMAT(ie) == '%')
		    call pargstr (IE_XFORMAT(ie))
		else
		    call pargstr ("%g")
		if (IE_YFORMAT(ie) == '%')
		    call pargstr (IE_YFORMAT(ie))
		else
		    call pargstr ("%g")
	}
	call sprintf (Memc[coords], IE_SZTITLE, Memc[title])
	    call pargr (wxcntr)
	    call pargr (wycntr)

	# Plot the radial profile and overplot the gaussian fit.
	if (gp != NULL) {
	    call sprintf (Memc[title], IE_SZTITLE,
		"%s: Radial profile at %s\n%s")
	        call pargstr (IE_IMAGE(ie))
	        call pargstr (Memc[coords])
		call pargstr (Memc[MI_RNAME(im)])

	    call ie_graph (gp, mode, pp, Memc[title], Memr[xs], Memr[ys],
		np, "", "")

	    if (fitplot && !IS_INDEF (fwhm)) {
		np = 51
		dx = rplot / (np - 1)
		do i = 0, np - 1
		    Memr[xs+i] = i * dx
		call nlvectorr (nl, Memr[xs], Memr[ys], np, 1)
		call gseti (gp, G_PLTYPE, 2)
		call gpline (gp, Memr[xs], Memr[ys], np)
		call gseti (gp, G_PLTYPE, 1)
	    }
	    call gseti (gp, G_PLTYPE, 2)

	    call printf (
		"%7.2f %7.4g %7.4g %7.4g %5.2f %5d %8.2f %8.2f %8.2f %8.2f\n")
	        call pargr (mag)
	        call pargd (sumo)
	        call pargd (sums / no)
	        call pargr (zcntr)
	        call pargr (e)
	        call pargr (pa)
	        call pargr (r)
		call pargr (efwhm)
	        call pargr (fwhm)
		call pargr (dfwhm)

	} else {
	    if (IE_LASTKEY(ie) != 'a') {
		call printf (label1)
		call printf (label2)
	    }

	    if (xcntr != wxcntr || ycntr != wycntr) {
		call printf ("%7.2f %7.2f: %s = %s\n")
		    call pargr (xcntr)
		    call pargr (ycntr)
		    call pargstr (IE_WCSNAME(ie))
		    call pargstr (Memc[coords])
	    } else {
		call printf ("%7.2f %7.2f\n")
		    call pargr (xcntr)
		    call pargr (ycntr)
		    call pargstr (IE_WCSNAME(ie))
	    }
	    call printf (
		"%7.2f %7.4g %7.4g %7.4g %5.2f %5d %8.2f %8.2f %8.2f %8.2f\n")
	        call pargr (mag)
	        call pargd (sumo)
	        call pargd (sums / no)
	        call pargr (zcntr)
	        call pargr (e)
	        call pargr (pa)
	        call pargr (r)
		call pargr (efwhm)
	        call pargr (fwhm)
		call pargr (dfwhm)
	}

	if (IE_LOGFD(ie) != NULL) {
	    if (IE_LASTKEY(ie) != 'a') {
		call fprintf (IE_LOGFD(ie), label1)
		call fprintf (IE_LOGFD(ie), label2)
	    }

	    if (xcntr != wxcntr || ycntr != wycntr) {
		call fprintf (IE_LOGFD(ie), "%7.2f %7.2f: %s = %s\n")
		    call pargr (xcntr)
		    call pargr (ycntr)
		    call pargstr (IE_WCSNAME(ie))
		    call pargstr (Memc[coords])
	    } else {
		call fprintf (IE_LOGFD(ie), "%7.2f %7.2f\n")
		    call pargr (xcntr)
		    call pargr (ycntr)
		    call pargstr (IE_WCSNAME(ie))
	    }
	    call fprintf (IE_LOGFD(ie),
		"%7.2f %7.4g %7.4g %7.4g %5.2f %5d %8.2f %8.2f %8.2f %8.2f\n")
	        call pargr (mag)
	        call pargd (sumo)
	        call pargd (sums / no)
	        call pargr (zcntr)
	        call pargr (e)
	        call pargr (pa)
	        call pargr (r)
		call pargr (efwhm)
	        call pargr (fwhm)
		call pargr (dfwhm)
	}

	if (gp == NULL)
	   call clcpset (pp)
	else
	    IE_PP(ie) = pp

	call nlfreer (nl)
	call sfree (sp)
end


# IE_CENTER -- Find the center of gravity from the marginal distributions.

procedure ie_center (im, radius, xcntr, ycntr)

pointer	im
real	radius
real	xcntr, ycntr

int	i, j, k, x1, x2, y1, y2, nx, ny, npts
real	xlast, ylast
real	mean, sum, sum1, sum2, sum3, asumr()
pointer	data, ptr, ie_gdata()
errchk	ie_gdata

begin
	# Find the center of a star image given approximate coords.  Uses
	# Mountain Photometry Code Algorithm as outlined in Stellar Magnitudes
	# from Digital Images.

	do k = 1, 3 {
	    # Extract region around center
	    xlast = xcntr
	    ylast = ycntr
	    x1 = xcntr - radius + 0.5
	    x2 = xcntr + radius + 0.5
	    y1 = ycntr - radius + 0.5
	    y2 = ycntr + radius + 0.5
	    data = ie_gdata (im, x1, x2, y1, y2)

	    nx = x2 - x1 + 1
	    ny = y2 - y1 + 1
	    npts = nx * ny

	    # Find center of gravity for marginal distributions above mean.
	    sum = asumr (Memr[data], npts)
	    mean = sum / nx
	    sum1 = 0.
	    sum2 = 0.

	    do i = x1, x2 {
	        ptr = data + i - x1
		sum3 = 0.
		do j = y1, y2 {
		    sum3 = sum3 + Memr[ptr]
		    ptr = ptr + nx
		}
		sum3 = sum3 - mean
		if (sum3 > 0.) {
		    sum1 = sum1 + i * sum3
		    sum2 = sum2 + sum3
		}
	    }
	    xcntr = sum1 / sum2

	    ptr = data
	    mean = sum / ny
	    sum1 = 0.
	    sum2 = 0.
	    do j = y1, y2 {
		sum3 = 0.
		do i = x1, x2 {
		    sum3 = sum3 + Memr[ptr]
		    ptr = ptr + 1
		}
		sum3 = sum3 - mean
		if (sum3 > 0.) {
		    sum1 = sum1 + j * sum3
		    sum2 = sum2 + sum3
		}
	    }
	    ycntr = sum1 / sum2

	    if (int(xcntr) == int(xlast) && int(ycntr) == int(ylast))
		break
	}
end


# IE_GAUSS -- Gaussian function used in NLFIT.  The parameters are the
# amplitude and sigma squared and the input variable is the radius.

procedure ie_gauss (x, nvars, p, np, z)

real	x[nvars]		#I Input variables
int	nvars			#I Number of variables
real	p[np]			#I Parameter vector
real	np			#I Number of parameters
real	z			#O Function return

real	r2

begin
	r2 = x[1]**2 / (2 * p[2])
	if (abs (r2) > 20.)
	    z = 0.
	else
	    z = p[1] * exp (-r2)
end


# IE_DGAUSS -- Gaussian function and derivatives used in NLFIT.  The parameters
# are the amplitude and sigma squared and the input variable is the radius.

procedure ie_dgauss (x, nvars, p, dp, np, z, der)

real	x[nvars]		#I Input variables
int	nvars			#I Number of variables
real	p[np]			#I Parameter vector
real	dp[np]			#I Dummy array of parameters increments
real	np			#I Number of parameters
real	z			#O Function return
real	der[np]			#O Derivatives

real	r2

begin
	r2 = x[1]**2 / (2 * p[2])
	if (abs (r2) > 20.) {
	    z = 0.
	    der[1] = 0.
	    der[2] = 0.
	} else {
	    der[1] = exp (-r2)
	    z = p[1] * der[1]
	    der[2] = z * r2 / p[2]
	}
end
