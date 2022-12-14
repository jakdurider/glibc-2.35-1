.file "logb.s"


// Copyright (c) 2000 - 2003, Intel Corporation
// All rights reserved.
//
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
// * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// * The name of Intel Corporation may not be used to endorse or promote
// products derived from this software without specific prior written
// permission.

// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL INTEL OR ITS
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
// OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Intel Corporation is the author of this code, and requests that all
// problem reports or change requests be submitted to it directly at
// http://www.intel.com/software/products/opensource/libraries/num.htm.
//
// History
//==============================================================
// 02/02/00 Initial version
// 02/16/00 Modified to conform to C9X
// 03/16/00 Improved speed
// 04/04/00 Unwind support added
// 05/30/00 Fixed bug when x double-extended denormal
// 08/15/00 Bundle added after call to __libm_error_support to properly
//          set [the previously overwritten] GR_Parameter_RESULT.
// 05/20/02 Cleaned up namespace and sf0 syntax
// 01/20/03 Improved performance
//
// API
//==============================================================
// double logb( double x );
//
// Overview of operation
//==============================================================
// The logb function extracts the exponent of x as an integer in
// floating-point format.
// logb computes log2 of x as a double
//
// logb is similar to ilogb but differs in the  following ways:
//         +-inf
//            ilogb: returns INT_MAX
//             logb: returns +inf
//         Nan  returns FP_LOGBNAN (which is either INT_MAX or INT_MIN)
//            ilogb: returns INT_MAX (7fffffff)
//             logb: returns QNAN (quietized SNAN)
//         0    returns FP_ILOGB0 (which is either INT_MIN or -INT_MAX)
//            ilogb: returns -INT_MAX (80000001)
//             logb: returns -inf, raises the divide-by-zero exception,
//                   and calls libm_error_support to set domain error
//
// Registers used
//==============================================================
// general registers used:
// r26 -> r38
// r35 -> r38 used as parameters to error path
//
// predicate registers used:
// p6, p7, p8
// floating-point registers used:
// f9, f10, f11
// f8, input

rExpBias            = r26
rExpMask            = r27
rSignexp_x          = r28
rExp_x              = r29
rTrueExp_x          = r30
rExp_2to64          = r31

GR_SAVE_PFS         = r32
GR_SAVE_B0          = r33
GR_SAVE_GP          = r34

GR_Parameter_X      = r35
GR_Parameter_Y      = r36
GR_Parameter_RESULT = r37
GR_Parameter_TAG    = r38

fExp_in_signif      = f9
fNorm_x             = f10
fFloat_Exp          = f10
f2to64              = f11

.section .text
GLOBAL_LIBM_ENTRY(logb)

// X NORMAL
// TrueExp_x = exp(f8) - 0xffff
// sig = TrueExp_x
// f8 = convert_to_fp (sig))
{ .mfi
      getf.exp        rSignexp_x = f8
      fclass.m        p8,p0 = f8, 0x0b   // Test for x unorm
      mov             rExpBias = 0xffff  // Exponent bias
}
{ .mfi
      nop.m           0
      fnorm.s1        fNorm_x = f8
      mov             rExpMask = 0x1ffff // Exponent mask
}
;;

// Form signexp of 2^64 in case need to scale denormal
{ .mfb
      mov             rExp_2to64 = 0x1003f
      fclass.m        p6,p0 = f8, 0x1e3  // Test x natval, nan, inf
(p8)  br.cond.spnt    LOGB_DENORM        // Branch if x unorm
}
;;

LOGB_COMMON:
// Return here from LOGB_DENORM
{ .mfi
      and             rExp_x = rSignexp_x, rExpMask // Get biased exponent
      fclass.m        p7,p0 = f8, 0x07   // Test x zero
      nop.i           0
}
;;

// X NAN or INFINITY, return f8 * f8
{ .mfb
      sub             rTrueExp_x = rExp_x, rExpBias // Get true exponent
(p6)  fma.d.s0        f8= f8,f8,f0       // Result if x natval, nan, inf
(p6)  br.ret.spnt     b0                 // Exit if x natval, nan, inf
}
;;

{ .mib
      setf.sig        fExp_in_signif = rTrueExp_x // Exponent as integer in fp
      nop.i 999
(p7)  br.cond.spnt    LOGB_ZERO
}
;;

// Result can be represented in less than 24 bits, so no precision completer
// is needed.
{ .mfb
      nop.m           0
      fcvt.xf         f8 = fExp_in_signif
      br.ret.sptk     b0                 // Exit main path, 0 < |x| < inf
}
;;

LOGB_DENORM:
// Form 2^64 in case need to scale denormal
// Check to see if double-extended denormal
{ .mfi
      setf.exp        f2to64 = rExp_2to64
      fclass.m        p8,p0 = fNorm_x, 0x0b
      nop.i           0
}
;;

{ .mfi
      nop.m           0
      fcmp.eq.s0      p7,p0 = f8, f0           // Dummy op to set denormal flag
      nop.i           0
}
;;

// If double-extended denormal add 64 to exponent bias for scaling
// If double-extended denormal form x * 2^64 which is normal
{ .mfi
(p8)  add             rExpBias = 64, rExpBias
(p8)  fmpy.s1         fNorm_x = fNorm_x, f2to64
      nop.i           0
}
;;

// Logic is the same as normal path but use normalized input
{ .mib
      getf.exp        rSignexp_x = fNorm_x
      nop.i           0
      br.cond.sptk    LOGB_COMMON              // Return to main path
}
;;

LOGB_ZERO:
// Here if x zero
// f10  = -|f8|
// f9  = 1.0/f10 = -1.0/|f8| = -inf

{ .mmf
      alloc           r32=ar.pfs,1,2,4,0
      mov             GR_Parameter_TAG = 151  // Error code
      fmerge.ns       f10 = f0,f8
}
;;

{ .mfb
      nop.m           0
      frcpa.s0        f9,p6 = f1,f10          // Produce -inf, Z flag
      br.cond.sptk    __libm_error_region     // Call error support
}
;;

GLOBAL_LIBM_END(logb)
libm_alias_double_other (logb, logb)


LOCAL_LIBM_ENTRY(__libm_error_region)
.prologue

{ .mfi
        add   GR_Parameter_Y=-32,sp           // Parameter 2 value
        nop.f 0
.save   ar.pfs,GR_SAVE_PFS
        mov  GR_SAVE_PFS=ar.pfs               // Save ar.pfs
}
{ .mfi
.fframe 64
        add sp=-64,sp                         // Create new stack
        nop.f 0
        mov GR_SAVE_GP=gp                     // Save gp
};;

{ .mmi
        stfd [GR_Parameter_Y] = f0,16         // STORE Parameter 2 on stack
        add GR_Parameter_X    = 16,sp         // Parameter 1 address
.save   b0, GR_SAVE_B0
        mov GR_SAVE_B0=b0                     // Save b0
};;

.body
{ .mib
        stfd [GR_Parameter_X] = f8            // STORE Parameter 1 on stack
        add   GR_Parameter_RESULT = 0,GR_Parameter_Y    // Parameter 3 address
        nop.b 0
}
{ .mib
        stfd [GR_Parameter_Y] = f9            // Store Parameter 3 on stack
        add   GR_Parameter_Y = -16,GR_Parameter_Y
        br.call.sptk b0=__libm_error_support# // Call error handling function
};;

{ .mmi
        add   GR_Parameter_RESULT = 48,sp
        nop.m 0
        nop.i 0
};;

{ .mmi
        ldfd  f8 = [GR_Parameter_RESULT]       // Get return result off stack
.restore sp
        add   sp = 64,sp                       // Restore stack pointer
        mov   b0 = GR_SAVE_B0                  // Restore return address
};;

{ .mib
        mov   gp = GR_SAVE_GP                  // Restore gp
        mov   ar.pfs = GR_SAVE_PFS             // Restore ar.pfs
        br.ret.sptk   b0
};;

LOCAL_LIBM_END(__libm_error_region)


.type   __libm_error_support#,@function
.global __libm_error_support#
