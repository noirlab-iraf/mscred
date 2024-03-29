include	<mach.h>
include	<ctype.h>
include	<error.h>
include	<imhdr.h>
include	<imset.h>
include	<pmset.h>
include	<mwset.h>
include	<syserr.h>


# XT_PMMAP -- Open a pixel mask READ_ONLY.
#
# This routine maps multiple types of mask files and designations.
# It matches the mask coordinates to the reference image based on the
# physical coordinate system so the mask may be of a different size.
# The mask name is returned so that the task has the name pointed to by "BPM".
# A null filename is allowed and returns NULL.
#
# Modified to use xt_maskname with the reference image extension name.

pointer procedure yt_pmmap (pmname, refim, mname, sz_mname)

char	pmname[ARB]		#I Pixel mask name
pointer	refim			#I Reference image pointer
char	mname[ARB]		#O Expanded mask name
int	sz_mname		#O Size of expanded mask name

int	i, flag, nowhite()
pointer	sp, fname, extname, im, ref, yt_pmmap1()
bool	streq()
errchk	yt_pmmap1

begin
	call smark (sp)
	call salloc (fname, SZ_FNAME, TY_CHAR)
	call salloc (extname, SZ_FNAME, TY_CHAR)

	im = NULL
	i = nowhite (pmname, Memc[fname], SZ_FNAME)
	if (Memc[fname] == '!') {
	    iferr (call imgstr (refim, Memc[fname+1], Memc[fname], SZ_FNAME))
		Memc[fname] = EOS
	} else if (streq (Memc[fname], "BPM")) {
	    iferr (call imgstr (refim, "BPM", Memc[fname], SZ_FNAME))
		Memc[fname] = EOS
	} else if (streq (Memc[fname], "^BPM")) {
	    flag = INVERT_MASK
	    iferr (call imgstr (refim, "BPM", Memc[fname+1], SZ_FNAME))
		Memc[fname] = EOS
	}

	if (Memc[fname] == '^') {
	    flag = INVERT_MASK
	    call strcpy (Memc[fname+1], Memc[fname], SZ_FNAME)
	} else
	    flag = NO

	if (streq (Memc[fname], "EMPTY"))
	    ref = refim
	else
	    ref = NULL

	if (Memc[fname] != EOS) {
	    iferr (im = yt_pmmap1 (Memc[fname], ref, refim, flag)) {
	        ifnoerr (call imgstr (refim, "extname", Memc[extname],
		    SZ_FNAME)) {
		    call xt_maskname (Memc[fname], Memc[extname], READ_ONLY,
		        Memc[fname], SZ_FNAME)
		    im = yt_pmmap1 (Memc[fname], ref, refim, flag)
		} else
		    im = yt_pmmap1 (Memc[fname], ref, refim, flag)
	    }
	}
	call strcpy (Memc[fname], mname, sz_mname)

	call sfree (sp)
	return (im)
end


# XT_PMUNMAP -- Unmap a mask image.
# Note that the imio pointer may be purely an internal pointer opened
# with im_pmmapo so we need to free the pl pointer explicitly.

procedure yt_pmunmap (im)

pointer	im			#I IMIO pointer for mask

pointer	pm
int	imstati()

begin
	pm = imstati (im, IM_PMDES)
	call pm_close (pm)
	call imseti (im, IM_PMDES, NULL)
	call imunmap (im)
end


# XT_PMMAP1 -- Open a pixel mask READ_ONLY.  The input mask may be
# a pixel list image, a non-pixel list image, or a text file.
# Return error if the pixel mask cannot be opened.  For pixel masks
# or image masks match the WCS.

pointer procedure yt_pmmap1 (pmname, ref, refim, flag)

char	pmname[ARB]		#I Pixel mask name
pointer	ref			#I Reference image for pixel mask
pointer	refim			#I Reference image for image or text
int	flag			#I Mask flag

int	imstati(),  errcode()
pointer	im, pm
pointer	im_pmmap(), yt_pmimmap(), yt_pmtext(), yt_pmsection()
bool	streq()
errchk	yt_match

begin
	im = NULL

	if (streq (pmname, "STDIN"))
	    im = yt_pmtext (pmname, refim, flag)

	else if (pmname[1] == '[')
	    im = yt_pmsection (pmname, refim, flag)

	else {
	    ifnoerr (im = im_pmmap (pmname, READ_ONLY, ref)) {
		call yt_match (im, refim)
		if (flag == INVERT_MASK) {
		    pm = imstati (im, IM_PMDES)
		    call yt_pminvert (pm)
		    call imseti (im, IM_PMDES, pm)
		}
	    } else {
		switch (errcode()) {
		case SYS_IKIOPEN, SYS_FOPNNEXFIL, SYS_PLBADSAVEF, SYS_FOPEN:
		    ifnoerr (im = yt_pmimmap (pmname, refim, flag))
			call yt_match (im, refim)
		    else {
			switch (errcode()) {
			case SYS_IKIOPEN:
			    im = yt_pmtext (pmname, refim, flag)
			default:
			    call erract (EA_ERROR)
			}
		    }
		default:
		    call erract (EA_ERROR)
		}
	    }
	}

	return (im)
end


# XT_PMIMMAP -- Open a pixel mask from a non-pixel list image.
# Return error if the image cannot be opened.

pointer procedure yt_pmimmap (pmname, refim, flag)

char	pmname[ARB]		#I Image name
pointer	refim			#I Reference image pointer
int	flag			#I Mask flag

int	i, ndim, npix, rop, val
pointer	sp, v1, v2, im_in, im_out, pm, mw, data

int	imstati(), imgnli()
pointer immap(), pm_newmask(), im_pmmapo(), imgl1i(), mw_openim()
errchk	immap, mw_openim, im_pmmapo

begin
	call smark (sp)
	call salloc (v1, IM_MAXDIM, TY_LONG)
	call salloc (v2, IM_MAXDIM, TY_LONG)

	call amovkl (long(1), Meml[v1], IM_MAXDIM)
	call amovkl (long(1), Meml[v2], IM_MAXDIM)

	im_in = immap (pmname, READ_ONLY, 0)
	pm = imstati (im_in, IM_PMDES)
	if (pm != NULL)
	    return (im_in)
	pm = pm_newmask (im_in, 16)

	ndim = IM_NDIM(im_in)
	npix = IM_LEN(im_in,1)

	if (flag == INVERT_MASK)
	    rop = PIX_NOT(PIX_SRC)
	else
	    rop = PIX_SRC

	while (imgnli (im_in, data, Meml[v1]) != EOF) {
	    if (flag == INVERT_MASK) {
		do i = 0, npix-1 {
		    val = Memi[data+i]
		    if (val <= 0)
		       Memi[data+i] = 1
		    else
		       Memi[data+i] = 0
		}
	    } else {
		do i = 0, npix-1 {
		    val = Memi[data+i]
		    if (val < 0)
		       Memi[data+i] = 0
		}
	    }
	    call pmplpi (pm, Meml[v2], Memi[data], 0, npix, rop)
	    call amovl (Meml[v1], Meml[v2], ndim)
	}

	im_out = im_pmmapo (pm, im_in)
	data = imgl1i (im_out)		# Force I/O to set header
	mw = mw_openim (im_in)		# Set WCS
	call mw_saveim (mw, im_out)
	call mw_close (mw)

	#call imunmap (im_in)
	call yt_pmunmap (im_in)
	call sfree (sp)
	return (im_out)
end


# XT_PMTEXT -- Create a pixel mask from a text file of rectangles.
# Return error if the file cannot be opened.
# This routine only applies to the first 2D plane.

pointer procedure yt_pmtext (pmname, refim, flag)

char	pmname[ARB]		#I Image name
pointer	refim			#I Reference image pointer
int	flag			#I Mask flag

int	fd, nc, nl, c1, c2, l1, l2, nc1, nl1, rop
pointer	pm, im, mw, dummy

int	open(), fscan(), nscan()
pointer	pm_newmask(), im_pmmapo(), imgl1i(), mw_openim()
errchk	open,im_pmmapo

begin
	fd = open (pmname, READ_ONLY, TEXT_FILE)
	pm = pm_newmask (refim, 16)

	nc = IM_LEN(refim,1)
	nl = IM_LEN(refim,2)

	if (flag == INVERT_MASK)
	    call pl_box (pm, 1, 1, nc, nl, PIX_SET+PIX_VALUE(1))

	while (fscan (fd) != EOF) {
	    call gargi (c1)
	    call gargi (c2)
	    call gargi (l1)
	    call gargi (l2)
	    if (nscan() != 4) {
		if (nscan() == 2) {
		    l1 = c2
		    c2 = c1
		    l2 = l1
		} else
		    next
	    }

	    c1 = max (1, c1)
	    c2 = min (nc, c2)
	    l1 = max (1, l1)
	    l2 = min (nl, l2)
	    nc1 = c2 - c1 + 1
	    nl1 = l2 - l1 + 1
	    if (nc1 < 1 || nl1 < 1)
		next

	    # Select mask value based on shape of rectangle.
	    if (flag == INVERT_MASK)
		rop = PIX_CLR
	    else if (nc1 <= nl1)
		rop = PIX_SET+PIX_VALUE(2)
	    else
		rop = PIX_SET+PIX_VALUE(3)

	    # Set mask rectangle.
	    call pm_box (pm, c1, l1, c2, l2, rop)
	}

	call close (fd)
	im = im_pmmapo (pm, refim)
	dummy = imgl1i (im)		# Force I/O to set header
	mw = mw_openim (refim)		# Set WCS
	call mw_saveim (mw, im)
	call mw_close (mw)

	return (im)
end


# XT_PMSECTION -- Create a pixel mask from an image section.
# This only applies the mask to the first plane of the image.

pointer procedure yt_pmsection (section, refim, flag)

char	section[ARB]		#I Image section
pointer	refim			#I Reference image pointer
int	flag			#I Mask flag

int	i, j, ip, temp, a[2], b[2], c[2], rop, ctoi()
pointer	pm, im, mw, dummy, pm_newmask(), im_pmmapo(), imgl1i(), mw_openim()
errchk	im_pmmapo
define  error_  99

begin
	# This is currently only for 1D and 2D images.
	if (IM_NDIM(refim) > 2)
	    call error (1, "Image sections only allowed for 1D and 2D images")

        # Decode the section string.
	call amovki (1, a, 2)
	call amovki (1, b, 2)
	call amovki (1, c, 2)
	do i = 1, IM_NDIM(refim)
	    b[i] = IM_LEN(refim,i)

        ip = 1
        while (IS_WHITE(section[ip]))
            ip = ip + 1
        if (section[ip] == '[') {
            ip = ip + 1

	    do i = 1, IM_NDIM(refim) {
		while (IS_WHITE(section[ip]))
		    ip = ip + 1

		# Get a:b:c.  Allow notation such as "-*:c"
		# (or even "-:c") where the step is obviously negative.

		if (ctoi (section, ip, temp) > 0) {                 # a
		    a[i] = temp
		    if (section[ip] == ':') {
			ip = ip + 1
			if (ctoi (section, ip, b[i]) == 0)             # a:b
			    goto error_
		    } else
			b[i] = a[i]
		} else if (section[ip] == '-') {                    # -*
		    temp = a[i]
		    a[i] = b[i]
		    b[i] = temp
		    ip = ip + 1
		    if (section[ip] == '*')
			ip = ip + 1
		} else if (section[ip] == '*')                      # *
		    ip = ip + 1
		if (section[ip] == ':') {                           # ..:step
		    ip = ip + 1
		    if (ctoi (section, ip, c[i]) == 0)
			goto error_
		    else if (c[i] == 0)
			goto error_
		}
		if (a[i] > b[i] && c[i] > 0)
		    c[i] = -c[i]

		while (IS_WHITE(section[ip]))
		    ip = ip + 1
		if (i < IM_NDIM(refim)) {
		    if (section[ip] != ',')
			goto error_
		} else {
		    if (section[ip] != ']')
			goto error_
		}
		ip = ip + 1
	    }
	}

	# In this case make the values be increasing only.
	do i = 1, IM_NDIM(refim)
	    if (c[i] < 0) {
		temp = a[i]
		a[i] = b[i]
		b[i] = temp
		c[i] = -c[i]
	    }

	# Make the mask.
	pm = pm_newmask (refim, 16)

	if (flag == INVERT_MASK) {
	    rop = PIX_SET+PIX_VALUE(1)
	    call pm_box (pm, 1, 1, IM_LEN(refim,1), IM_LEN(refim,2), rop)
	    rop = PIX_CLR
	} else
	    rop = PIX_SET+PIX_VALUE(1)

	if (c[1] == 1 && c[2] == 1)
	    call pm_box (pm, a[1], a[2], b[1], b[2], rop)

	else if (c[1] == 1)
	    for (i=a[2]; i<=b[2]; i=i+c[2])
		call pm_box (pm, a[1], i, b[1], i, rop)

	else
	    for (i=a[2]; i<=b[2]; i=i+c[2])
		for (j=a[1]; j<=b[1]; j=j+c[1])
		    call pm_point (pm, j, i, rop)

	im = im_pmmapo (pm, refim)
	dummy = imgl1i (im)		# Force I/O to set header
	mw = mw_openim (refim)		# Set WCS
	call mw_saveim (mw, im)
	call mw_close (mw)

	return (im)

error_
        call error (1, "Error in image section specification")
end


# XT_PMINVERT -- Invert a pixel mask by changing 0 to 1 and non-zero to zero.

procedure yt_pminvert (pm)

pointer	pm		#I Pixel mask to be inverted

int	i, naxes, axlen[IM_MAXDIM], depth, npix, val
pointer	sp, v, buf, one
bool	pm_linenotempty()

begin
	call pm_gsize (pm, naxes, axlen, depth)

	call smark (sp)
	call salloc (v, IM_MAXDIM, TY_LONG)
	call salloc (buf, axlen[1], TY_INT)
	call salloc (one, 6, TY_INT)

	npix = axlen[1]
	RLI_LEN(one) = 2
	RLI_AXLEN(one) = npix
	Memi[one+3] = 1
	Memi[one+4] = npix
	Memi[one+5] = 1

	call amovkl (long(1), Meml[v], IM_MAXDIM)
	repeat {
	    if (pm_linenotempty (pm, Meml[v])) {
		call pmglpi (pm, Meml[v], Memi[buf], 0, npix, 0)
		do i = 0, npix-1 {
		    val = Memi[buf+i]
		    if (val == 0)
			Memi[buf+i] = 1
		    else
			Memi[buf+i] = 0
		}
		call pmplpi (pm, Meml[v], Memi[buf], 0, npix, PIX_SRC)
	    } else
		call pmplri (pm, Meml[v], Memi[one], 0, npix, PIX_SRC)
	    
	    do i = 2, naxes {
		Meml[v+i-1] = Meml[v+i-1] + 1
		if (Meml[v+i-1] <= axlen[i])
		    break
		else if (i < naxes)
		    Meml[v+i-1] = 1
	    }
	} until (Meml[v+naxes-1] > axlen[naxes])

	call sfree (sp)
end


# XT_MATCH -- Set the pixel mask to match the reference image.
# This matches sizes and physical coordinates and allows the
# original mask to be smaller or larger than the reference image.
# Subsequent use of the pixel mask can then work in the logical
# coordinates of the reference image.  The mask values are the maximum
# of the mask values which overlap each reference image pixel.
# A null input returns a null output.

procedure yt_match (im, refim)

pointer	im			#U Pixel mask image pointer
pointer	refim			#I Reference image pointer

int	i, j, k, l, i1, i2, j1, j2, nc, nl, ncpm, nlpm, nx, val
double	x1, x2, y1, y2, lt[6], lt1[6], lt2[6]
long	vold[IM_MAXDIM], vnew[IM_MAXDIM]
pointer	pm, pmnew, imnew, mw, ctx, cty, bufref, bufpm

int	imstati()
pointer	pm_open(), mw_openim(), im_pmmapo(), imgl1i(), mw_sctran()
bool	pm_empty(), pm_linenotempty()
errchk	pm_open, mw_openim, im_pmmapo

begin
	if (im == NULL)
	    return

	# Set sizes.
	nc = IM_LEN(refim,1)
	nl = IM_LEN(refim,2)
	ncpm = IM_LEN(im,1)
	nlpm = IM_LEN(im,2)

	# If the mask is empty and the sizes are the same then it does not
	# matter if the two are actually matched in physical coordinates.
	pm = imstati (im, IM_PMDES)
	if (pm_empty(pm) && nc == ncpm && nl == nlpm)
	    return

	# Compute transformation between reference (logical) coordinates
	# and mask (physical) coordinates.

	mw = mw_openim (im)
	call mw_gltermd (mw, lt, lt[5], 2)
	call mw_close (mw)

	mw = mw_openim (refim)
	call mw_gltermd (mw, lt2, lt2[5], 2)
	call mw_close (mw)

	# Combine lterms.
	call mw_invertd (lt, lt1, 2)
	call mw_mmuld (lt1, lt2, lt, 2)
	call mw_vmuld (lt, lt[5], lt[5], 2)
	lt[5] = lt2[5] - lt[5]
	lt[6] = lt2[6] - lt[6]
	do i = 1, 6
	    lt[i] = nint (1D6 * (lt[i]-int(lt[i]))) / 1D6 + int(lt[i])

	# Check for a rotation.  For now don't allow any rotation.
	if (lt[2] != 0. || lt[3] != 0.)
	    call error (1, "Image and mask have a relative rotation")
	
	# Check for an exact match.
	if (lt[1] == 1D0 && lt[4] == 1D0 && lt[5] == 0D0 && lt[6] == 0D0 &&
	    nc == ncpm && nl == nlpm)
	    return

	# Set reference to mask coordinates.
	mw = mw_openim (im)
	call mw_sltermd (mw, lt, lt[5], 2)
	ctx = mw_sctran (mw, "logical", "physical", 1)
	cty = mw_sctran (mw, "logical", "physical", 2)

	# Create a new pixel mask of the required size and offset.
	# Do dummy image I/O to set the header.
	pmnew = pm_open (NULL)
	call pm_ssize (pmnew, 2, IM_LEN(refim,1), 27)
	imnew = im_pmmapo (pmnew, NULL)
	bufref = imgl1i (imnew)

	# Compute region of mask overlapping the reference image.
	call mw_ctrand (ctx, 1-0.5D0, x1, 1)
	call mw_ctrand (ctx, nc+0.5D0, x2, 1)
	i1 = max (1, nint(min(x1,x2)+1D-5))
	i2 = min (ncpm, nint(max(x1,x2)-1D-5))
	call mw_ctrand (cty, 1-0.5D0, y1, 1)
	call mw_ctrand (cty, nl+0.5D0, y2, 1)
	j1 = max (1, nint(min(y1,y2)+1D-5))
	j2 = min (nlpm, nint(max(y1,y2)-1D-5))

	# Set the new mask values to the maximum of all mask values falling
	# within each reference pixel in the overlap region.
	if (i1 <= i2 && j1 <= j2) {
	    nx = i2 - i1 + 1
	    vold[1] = i1
	    vnew[1] = 1

	    # If the scales are the same then it is just a problem of
	    # padding.  In this case use range lists for speed.
	    if (lt[1] == 1D0 && lt[4] == 1D0) {
		call malloc (bufpm, 3+3*nc, TY_INT)
		k = nint (lt[5])
		l = nint (lt[6])
		do j = max(1-l,j1), min(nl-l,j2) {
		    vold[2] = j
		    call yt_glri (pm, vold, Memi[bufpm], 0, nc, PIX_SRC)
		    if (k != 0) {
			bufref = bufpm
			do i = 2, Memi[bufpm] {
			    bufref = bufref + 3
			    Memi[bufref] = Memi[bufref] + k
			}
		    }
		    vnew[2] = j + l
		    call pmplri (pmnew, vnew, Memi[bufpm], 0, nc, PIX_SRC)
		}
		bufref = NULL

	    # Do all the geometry and pixel size matching.  This can
	    # be slow.
	    } else {
		call malloc (bufpm, nx, TY_INT)
		call malloc (bufref, nc, TY_INT)
		do j = 1, nl {
		    call mw_ctrand (cty, j-0.5D0, y1, 1)
		    call mw_ctrand (cty, j+0.5D0, y2, 1)
		    j1 = max (1, nint(min(y1,y2)+1D-5))
		    j2 = min (nlpm, nint(max(y1,y2)-1D-5))
		    if (j2 < j1)
			next

		    vnew[2] = j
		    call aclri (Memi[bufref], nc)
		    do l = j1, j2 {
			vold[2] = l
			if (!pm_linenotempty (pm, vold))
			    next
			call pmglpi (pm, vold, Memi[bufpm], 0, nx, 0)
			do i = 1, nc {
			    call mw_ctrand (ctx, i-0.5D0, x1, 1)
			    call mw_ctrand (ctx, i+0.5D0, x2, 1)
			    i1 = max (1, nint(min(x1,x2)+1D-5))
			    i2 = min (ncpm, nint(max(x1,x2)-1D-5))
			    if (i2 < i1)
				next
			    val = Memi[bufref+i-1]
			    do k = i1-vold[1], i2-vold[1]
				val = max (val, Memi[bufpm+k])
			    Memi[bufref+i-1] = val
			}
		    }
		    call pmplpi (pmnew, vnew, Memi[bufref], 0, nc, PIX_SRC)
		}
	    }
	    call mfree (bufref, TY_INT)
	    call mfree (bufpm, TY_INT)
	}

	call mw_close (mw)
	call yt_pmunmap (im)
	im = imnew
	call imseti (im, IM_PMDES, pmnew)
end


# Workaround for PLIO bug.


# Copyright(c) 1986 Association of Universities for Research in Astronomy Inc.

include	<plio.h>
include	<plset.h>

# PL_GLR -- Get a line segment as a range list, applying the given ROP to
# combine the pixels with those of the output list.

procedure yt_glri (pl, v, rl_dst, rl_depth, npix, rop)

pointer	pl			#I mask descriptor
long	v[PL_MAXDIM]		#I vector coords of line segment
int	rl_dst[ARB]		#O output range list
int	rl_depth		#I range list depth, bits
int	npix			#I number of pixels desired
int	rop			#I rasterop

int	mr, nr
pointer	sp, rl_out, rl_src, ll_src
pointer	pl_access()
int	yt_l2ri()
errchk	pl_access

begin
	ll_src = pl_access (pl,v)
	if (!R_NEED_DST(rop))
	    nr = yt_l2ri (Mems[ll_src], v[1], rl_dst, npix)
	else {
	    call smark (sp)
	    mr = min (RL_MAXLEN(pl), npix * 3)
	    call salloc (rl_src, mr, TY_INT)
	    call salloc (rl_out, mr, TY_INT)

	    nr = yt_l2ri (Mems[ll_src], v[1], Memi[rl_src], npix)
	    call pl_rangeropi (Memi[rl_src], 1, PL_MAXVAL(pl),
			              rl_dst,  1, MV(rl_depth),
				      Memi[rl_out], npix, rop)

	     # Copy out the edited range list.
	     call amovi (Memi[rl_out], rl_dst, RLI_LEN(rl_out))

	    call sfree (sp)
	}
end


# Copyright(c) 1986 Association of Universities for Research in Astronomy Inc.

#include	<plset.h>
#include	<plio.h>

# PL_L2R -- Convert a line list to a range list.  The length of the output
# range list is returned as the function value.

int procedure yt_l2ri (ll_src, xs, rl, npix)

short	ll_src[ARB]		#I input line list
int	xs			#I starting index in ll_src
int	rl[3,ARB] 		#O output range list
int	npix			#I number of pixels to convert

int	pv, hi
bool	skipword
int	opcode, data, ll_len, ll_first
int	x1, x2, i1, i2, xe, np, rn, ip
define	range_ 91
define	putrange_ 92
 
begin
	# Support old format line lists.
	if (LL_OLDFORMAT(ll_src)) {
	    ll_len = OLL_LEN(ll_src)
	    ll_first = OLL_FIRST
	} else {
	    ll_len = LL_LEN(ll_src)
	    ll_first = LL_FIRST(ll_src)
	}

	# No pixels?
	if (npix <= 0 || ll_len <= 0)
	    return (0)
 
	rn = RL_FIRST
	xe = xs + npix - 1
	skipword = false
	x1 = 1
	hi = 1

	do ip = ll_first, ll_len {
	    if (skipword) {
		skipword = false
		next
	    }

	    opcode = I_OPCODE(ll_src[ip])
	    data   = I_DATA(ll_src[ip])

	    switch (opcode) {
	    case I_ZN:
		pv = 0
		goto range_
	    case I_HN:
		pv = hi
range_
		# Determine inbounds region of segment.
		x2 = x1 + data - 1
		i1 = max (x1, xs)
		i2 = min (x2, xe)
		np = i2 - i1 + 1
		x1 = x2 + 1

	    case I_PN:
		pv = hi
		x2 = x1 + data - 1
		if (x2 < xs || x2 > xe)
		    np = 0
		else {
		    i1 = x2
		    np = 1
		}
		x1 = x2 + 1

	    case I_SH:
		hi = (int(ll_src[ip+1]) * I_SHIFT) + data
		skipword = true
		next
	    case I_IH:
		hi = hi + data
		next
	    case I_DH:
		hi = hi - data
		next

	    case I_IS, I_DS:
		if (opcode == I_IS)
		    hi = hi + data
		else
		    hi = hi - data

		i1 = max (x1, xs)
		i2 = min (x1, xe)
		np = i2 - i1 + 1
		x1 = x1 + 1
		pv = hi
	    }

	    # Output a range entry?
	    if (np > 0 && pv > 0) {
		rl[1,rn] = i1
		rl[2,rn] = np
		rl[3,rn] = pv
		rn = rn + 1
	    }

	    if (x1 > xe)
		break
	}

	RL_LEN(rl) = rn - 1
	RL_AXLEN(rl) = npix

	return (rn - 1)
end
