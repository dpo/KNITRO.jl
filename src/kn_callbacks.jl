# Callbacks utilities

"""
Structure specifying the callback context.

Each evaluation callbacks (for objective, gradient or hessian)
is attached to a unique callback context.

"""
mutable struct CallbackContext
    context::Ptr{Cvoid}
    # we have to keep a reference to the optimization model
    model::Model
    # we sometime need some user params
    userparams::Dict

    # oracle's callbacks are context dependent, so we store
    # them inside dedicated CallbackContext
    eval_f::Function
    eval_g::Function
    eval_h::Function
    eval_rsd::Function
    eval_jac_rsd::Function

    function CallbackContext(ptr::Ptr{Cvoid}, model::Model)
        return new(ptr, model, Dict())
    end
end

##################################################
# Utils
##################################################
function KN_set_cb_user_params(m::Model, cb::CallbackContext, userParams=nothing)
    # we have to store the model in the C model to use callbacks
    # function. So, we store the userParams inside the model
    if userParams != nothing
        cb.userparams[:data] = userParams
    end
    # we store the callback context inside KNITRO user data
    c_userdata = cb

    ret = @kn_ccall(set_cb_user_params, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, cb.context, c_userdata)
    _checkraise(ret)
end

"""
Specify which gradient option `gradopt` will be used to evaluate
the first derivatives of the callback functions.  If `gradopt=KN_GRADOPT_EXACT`
then a gradient evaluation callback must be set by `KN_set_cb_grad()`
(or `KN_set_cb_rsd_jac()` for least squares).

"""
function KN_set_cb_gradopt(m::Model, cb::CallbackContext, gradopt::Integer)
    ret = @kn_ccall(set_cb_gradopt, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Cint),
                    m.env, cb.context, gradopt)
    _checkraise(ret)
end

#--------------------
# Set relative step size
#--------------------
"""
Set an array of relative stepsizes to use for the finite-difference
gradient/Jacobian computations when using finite-difference
first derivatives.  Finite-difference step sizes `delta` in Knitro are
computed as:

     delta[i] = relStepSizes[i]*max(abs(x[i]),1);

The default relative step sizes for each component of `x` are sqrt(eps)
for forward finite differences, and eps^(1/3) for central finite
differences.  Use this function to overwrite the default values.

"""
function KN_set_cb_relstepsizes(m::Model, cb::CallbackContext, nindex::Integer, xRelStepSize::Cdouble)
    ret = @kn_ccall(set_cb_relstepsize, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Cdouble),
                    m.env, cb.context, nindex, xRelStepSize)
    _checkraise(ret)
end

function KN_set_cb_relstepsizes(m::Model, cb::CallbackContext, xIndex::Vector{Cint}, xRelStepSizes::Vector{Cdouble})
    ncon = length(xIndex)
    @assert length(xRelStepSizes) == ncon
    ret = @kn_ccall(set_cb_relstepsizes, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Ptr{Cint}, Ptr{Cdouble}),
                    m.env, cb.context, ncon, xIndex, xRelStepSizes)
    _checkraise(ret)
end

function KN_set_cb_relstepsizes(m::Model, cb::CallbackContext, xRelStepSizes::Vector{Cdouble})
    ret = @kn_ccall(set_cb_relstepsizes_all, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cdouble}),
                    m.env, cb.context, xRelStepSizes)
    _checkraise(ret)
end

#--------------------
# callback context getters
#--------------------
# TODO: dry this code with a macro
function KN_get_cb_number_cons(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_number_cons,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end

function KN_get_cb_objgrad_nnz(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_objgrad_nnz,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end

function KN_get_cb_jacobian_nnz(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_jacobian_nnz,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end

function KN_get_cb_hessian_nnz(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_hessian_nnz,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end

function KN_get_cb_number_rsds(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_number_rsds,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end

function KN_get_cb_rsd_jacobian_nnz(m::Model, cb::Ptr{Cvoid})
    num = Cint[0]
    ret = @kn_ccall(get_cb_rsd_jacobian_nnz,
                    Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cint}),
                    m.env, cb, num)
    _checkraise(ret)
    return num[1]
end


##################################################
# EvalRequest

# low level EvalRequest structure
"""
Low-level structure used to pass back evaluation information for evaluation
callbacks.

# Attributes
 * `evalRequestCode`: indicates the type of evaluation requested
 * `threadID`: the thread ID associated with this evaluation request;
                useful for multi-threaded, concurrent evaluations
 * `x`: values of unknown (primal) variables used for all evaluations
 * `lambda`: values of unknown dual variables/Lagrange multipliers
                     used for the evaluation of the Hessian
 * `sigma`: scalar multiplier for the objective component of the Hessian
 * `vec`: vector array value for Hessian-vector products (only used
          when user option hessopt=KN_HESSOPT_PRODUCT)

"""
mutable struct KN_eval_request
    evalRequestCode::Cint
    threadID::Cint
    x::Ptr{Cdouble}
    lambda::Ptr{Cdouble}
    sigma::Ptr{Cdouble}
    vec::Ptr{Cdouble}
end

# high level EvalRequest structure
"High level structure to wrap `KN_eval_request`."
mutable struct EvalRequest
    evalRequestCode::Cint
    threadID::Cint
    x::Array{Float64}
    lambda::Array{Float64}
    sigma::Float64
    vec::Array{Float64}
end

# Import low level request to Julia object
function EvalRequest(m::Model, evalRequest_::KN_eval_request)
    nx = KN_get_number_vars(m)
    nc = KN_get_number_cons(m)

    # import scaling
    sigma = (evalRequest_.sigma != C_NULL) ? unsafe_wrap(Array, evalRequest_.sigma, 1)[1] : 1.
    # we use only views to C arrays to avoid unnecessary copy
    return EvalRequest(evalRequest_.evalRequestCode,
                       evalRequest_.threadID,
                       unsafe_wrap(Array, evalRequest_.x, nx),
                       unsafe_wrap(Array, evalRequest_.lambda, nx + nc),
                       sigma,
                       unsafe_wrap(Array, evalRequest_.vec, nx))
end


##################################################
# EvalResult

# low level EvalResult structure
"""
Low-level structure used to return results information for evaluation callbacks.
The arrays (and their indices and sizes) returned in this structure are
local to the specific callback structure used for the evaluation.

# Attributes
* `obj`: objective function evaluated at `x` for EVALFC or
                     EVALFCGA request (funcCallback)
* `c`: (length nC) constraint values evaluated at `x` for
                     EVALFC or EVALFCGA request (funcCallback)
* `objGrad`: (length nV) objective gradient evaluated at `x` for
                     EVALGA request (gradCallback) or EVALFCGA request (funcCallback)
* `jac`: (length nnzJ) constraint Jacobian evaluated at `x` for
                     EVALGA request (gradCallback) or EVALFCGA request (funcCallback)
* `hess`: (length nnzH) Hessian evaluated at `x`, `lambda`, `sigma`
                     for EVALH or EVALH_NO_F request (hessCallback)
* `hessVec`: (length n=number variables in the model) Hessian-vector
                     product evaluated at `x`, `lambda`, `sigma`
                     for EVALHV or EVALHV_NO_F request (hessCallback)
* `rsd`: (length nR) residual values evaluated at `x` for EVALR
                     request (rsdCallback)
* `rsdJac`: (length nnzJ) residual Jacobian evaluated at `x` for
                     EVALRJ request (rsdJacCallback)

"""
mutable struct KN_eval_result
    obj::Ptr{Cdouble}
    c::Ptr{Cdouble}
    objGrad::Ptr{Cdouble}
    jac::Ptr{Cdouble}
    hess::Ptr{Cdouble}
    hessVec::Ptr{Cdouble}
    rsd::Ptr{Cdouble}
    rsdJac::Ptr{Cdouble}
end

# high level EvalRequest structure
mutable struct EvalResult
    obj::Array{Float64}
    c::Array{Float64}
    objGrad::Array{Float64}
    jac::Array{Float64}
    hess::Array{Float64}
    hessVec::Array{Float64}
    rsd::Array{Float64}
    rsdJac::Array{Float64}
end

function EvalResult(m::Model, cb::Ptr{Cvoid}, evalResult_::KN_eval_result)
    return EvalResult(
            unsafe_wrap(Array, evalResult_.obj, 1),
            unsafe_wrap(Array, evalResult_.c, KN_get_cb_number_cons(m, cb)),
            unsafe_wrap(Array, evalResult_.objGrad, KN_get_cb_objgrad_nnz(m, cb)),
            unsafe_wrap(Array, evalResult_.jac, KN_get_cb_jacobian_nnz(m, cb)),
            unsafe_wrap(Array, evalResult_.hess, KN_get_cb_hessian_nnz(m, cb)),
            unsafe_wrap(Array, evalResult_.hessVec, KN_get_number_vars(m)),
            unsafe_wrap(Array, evalResult_.rsd, KN_get_cb_number_rsds(m, cb)),
            unsafe_wrap(Array, evalResult_.rsdJac, KN_get_cb_rsd_jacobian_nnz(m, cb))
                     )
end


##################################################
# Callbacks wrappers
# 1/ for eval function
function eval_fc_wrapper(ptr_model::Ptr{Cvoid}, ptr_cb::Ptr{Cvoid},
                         evalRequest_::Ptr{Cvoid},
                         evalResults_::Ptr{Cvoid},
                         userdata_::Ptr{Cvoid})
    # load evalRequest object
    ptr0 = Ptr{KN_eval_request}(evalRequest_)
    evalRequest = unsafe_load(ptr0)::KN_eval_request

    # load evalResult object
    ptr = Ptr{KN_eval_result}(evalResults_)
    evalResult = unsafe_load(ptr)::KN_eval_result

    # and eventually, load callback context
    cb = unsafe_pointer_to_objref(userdata_)
    # we have to ensure that cb is a CallbackContext
    # otherwise, we tell KNITRO that a problem occurs by returning a
    # non-zero status
    if !isa(cb, CallbackContext)
        return Cint(32)
    end

    request = EvalRequest(cb.model, evalRequest)
    result = EvalResult(cb.model, ptr_cb, evalResult)

    cb.eval_f(ptr_model, ptr_cb, request, result, cb.userparams)

    return Cint(0)
end

# 2/ for gradient function
function eval_ga_wrapper(ptr_model::Ptr{Cvoid}, ptr_cb::Ptr{Cvoid},
                         evalRequest_::Ptr{Cvoid},
                         evalResults_::Ptr{Cvoid},
                         userdata_::Ptr{Cvoid})

    # load evalRequest object
    ptr0 = Ptr{KN_eval_request}(evalRequest_)
    evalRequest = unsafe_load(ptr0)::KN_eval_request

    # load evalResult object
    ptr = Ptr{KN_eval_result}(evalResults_)
    evalResult = unsafe_load(ptr)::KN_eval_result

    # and eventually, load callback context
    cb = unsafe_pointer_to_objref(userdata_)
    # we have to ensure that cb is a CallbackContext
    # otherwise, we tell KNITRO that a problem occurs by returning a
    # non-zero status
    if !isa(cb, CallbackContext)
        return Cint(32)
    end

    request = EvalRequest(cb.model, evalRequest)
    result = EvalResult(cb.model, ptr_cb, evalResult)

    cb.eval_g(ptr_model, ptr_cb, request, result, cb.userparams)

    return Cint(0)
end

# 3/ for hessian function
function eval_hess_wrapper(ptr_model::Ptr{Cvoid}, ptr_cb::Ptr{Cvoid},
                           evalRequest_::Ptr{Cvoid},
                           evalResults_::Ptr{Cvoid},
                           userdata_::Ptr{Cvoid})

    # load evalRequest object
    ptr0 = Ptr{KN_eval_request}(evalRequest_)
    evalRequest = unsafe_load(ptr0)::KN_eval_request

    # load evalResult object
    ptr = Ptr{KN_eval_result}(evalResults_)
    evalResult = unsafe_load(ptr)::KN_eval_result

    # and eventually, load callback context
    cb = unsafe_pointer_to_objref(userdata_)
    # we have to ensure that cb is a CallbackContext
    # otherwise, we tell KNITRO that a problem occurs by returning a
    # non-zero status
    if !isa(cb, CallbackContext)
        return Cint(32)
    end

    request = EvalRequest(cb.model, evalRequest)
    result = EvalResult(cb.model, ptr_cb, evalResult)

    cb.eval_h(ptr_model, ptr_cb, request, result, cb.userparams)

    return Cint(0)
end


################################################################################
################################################################################
################################################################################
################################################################################

# User callback should be of the form:
# callback(kc, cb, evalrequest, evalresult, usrparams)::Int

"""
    KN_add_eval_callback(m::Model, funccallback::Function)
    KN_add_eval_callback(m::Model, evalObj::Bool, indexCons::Vector{Cint},
                         funccallback::Function)

This is the routine for adding a callback for (nonlinear) evaluations
of objective and constraint functions.  This routine can be called
multiple times to add more than one callback structure (e.g. to create
different callback structures to handle different blocks of constraints).
This routine specifies the minimal information needed for a callback, and
creates the callback structure `cb`, which can then be passed to other
callback functions to set additional information for that callback.

# Parameters
* `evalObj`: boolean indicating whether or not any part of the objective
                  function is evaluated in the callback
* `indexCons`: (length nC) index of constraints evaluated in the callback
                  (set to NULL if nC=0)
* `funcCallback`: a function that evaluates the objective parts
                  (if evalObj=KNTRUE) and any constraint parts (specified by
                  nC and indexCons) involved in this callback; when
                  eval_fcga=KN_EVAL_FCGA_YES, this callback should also evaluate
                  the relevant first derivatives/gradients

# Returns
* `cb`: the callback structure that gets created by
                  calling this function; all the memory for this structure is
                  handled by Knitro

After a callback is created by `KN_add_eval_callback()`, the user can then specify
gradient information and structure through `KN_set_cb_grad()` and Hessian
information and structure through `KN_set_cb_hess()`.  If not set, Knitro will
approximate these.  However, it is highly recommended to provide a callback routine
to specify the gradients if at all possible as this will greatly improve the
performance of Knitro.  Even if a gradient callback is not provided, it is still
helpful to provide the sparse Jacobian structure through `KN_set_cb_grad()` to
improve the efficiency of the finite-difference gradient approximations.
Other optional information can also be set via `KN_set_cb_*()` functions as
detailed below.

"""
function KN_add_eval_callback(m::Model, funccallback::Function)
    # wrap eval_callback_wrapper as C function
    c_f = @cfunction(eval_fc_wrapper, Cint,
                     (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))

    # define callback context
    rfptr = Ref{Ptr{Cvoid}}()

    # add callback to context
    ret = @kn_ccall(add_eval_callback_all, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                    m.env, c_f, rfptr)
    _checkraise(ret)
    cb = CallbackContext(rfptr.x, m)

    # store function in callback environment:
    cb.eval_f = funccallback

    # store model in user params to access callback in C
    KN_set_cb_user_params(m, cb)

    return cb
end

function KN_add_eval_callback(m::Model, evalObj::Bool, indexCons::Vector{Cint},
                              funccallback::Function)
    nC = length(indexCons)

    # wrap eval_callback_wrapper as C function
    c_f = @cfunction(eval_fc_wrapper, Cint,
                     (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))

    # define callback context
    rfptr = Ref{Ptr{Cvoid}}()

    # add callback to context
    ret = @kn_ccall(add_eval_callback, Cint,
                    (Ptr{Cvoid}, KNBOOL, Cint, Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}),
                    m.env, KNBOOL(evalObj), nC, indexCons, c_f, rfptr)
    _checkraise(ret)
    cb = CallbackContext(rfptr.x, m)

    # store function in callback environment:
    cb.eval_f = funccallback

    KN_set_cb_user_params(m, cb)

    return cb
end

"""
    KN_set_cb_grad(m::Model, cb::CallbackContext, gradcallback;
                   nV::Integer=KN_DENSE, objGradIndexVars=C_NULL,
                   jacIndexCons=C_NULL, jacIndexVars=C_NULL)

This API function is used to set the objective gradient and constraint Jacobian
structure and also (optionally) a callback function to evaluate the objective
gradient and constraint Jacobian provided through this callback.

"""
function KN_set_cb_grad(m::Model, cb::CallbackContext, gradcallback;
                        nV::Integer=KN_DENSE, objGradIndexVars=C_NULL,
                        jacIndexCons=C_NULL, jacIndexVars=C_NULL)
    # check consistency of arguments
    if (nV == 0 || nV == KN_DENSE )
        (objGradIndexVars != C_NULL) && error("objGradIndexVars must be set to C_NULL when nV = $nV")
    else
        @assert (objGradIndexVars != C_NULL) && (length(objGradIndexVars) == nV)
    end

    nnzJ = KNLONG(0)
    if jacIndexCons != C_NULL && jacIndexVars != C_NULL
        @assert length(jacIndexCons) == length(jacIndexVars)
        nnzJ = KNLONG(length(jacIndexCons))
    end

    if gradcallback != nothing
        # store grad function inside model:
        cb.eval_g = gradcallback

        # wrap gradient wrapper as C function
        c_grad_g = @cfunction(eval_ga_wrapper, Cint,
                              (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))
    else
        c_grad_g = C_NULL
    end

    ret = @kn_ccall(set_cb_grad, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Ptr{Cint},
                     KNLONG, Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}),
                    m.env, cb.context, nV,
                    objGradIndexVars, nnzJ, jacIndexCons, jacIndexVars,
                    c_grad_g)
    _checkraise(ret)

    return nothing
end

"""
    KN_set_cb_hess(m::Model, cb::CallbackContext, nnzH::Integer, hesscallback::Function;
                   hessIndexVars1=C_NULL, hessIndexVars2=C_NULL)

This API function is used to set the structure and a callback function to
evaluate the components of the Hessian of the Lagrangian provided through this
callback.  KN_set_cb_hess() should only be used when defining a user-supplied
Hessian callback function (via the `hessopt=KN_HESSOPT_EXACT` user option).
When Knitro is approximating the Hessian, it cannot make use of the Hessian
sparsity structure.

"""
function KN_set_cb_hess(m::Model, cb::CallbackContext, nnzH::Integer, hesscallback::Function;
                        hessIndexVars1=C_NULL, hessIndexVars2=C_NULL)

    if nnzH == KN_DENSE_ROWMAJOR || nnzH == KN_DENSE_COLMAJOR
        @assert hessIndexVars1 == hessIndexVars2 == C_NULL
    else
        @assert hessIndexVars1 != C_NULL && hessIndexVars2 != C_NULL
        @assert length(hessIndexVars1) == length(hessIndexVars2) == nnzH
    end
    # store hessian function inside model:
    cb.eval_h = hesscallback

    # wrap gradient wrapper as C function
    c_hess = @cfunction(eval_hess_wrapper, Cint,
                        (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))

    ret = @kn_ccall(set_cb_hess, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, KNLONG, Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}),
                    m.env, cb.context, nnzH,
                    hessIndexVars1, hessIndexVars2, c_hess)
    _checkraise(ret)

    return nothing
end


##################################################
# Get callbacks info
##################################################
function KN_get_number_FC_evals(m::Model)
    fc_eval = Int32[0]
    ret = @kn_ccall(get_number_FC_evals, Cint, (Ptr{Cvoid}, Ptr{Cint}),
                    m.env, fc_eval)
    _checkraise(ret)
    return fc_eval[1]
end

function KN_get_number_GA_evals(m::Model)
    fc_eval = Int32[0]
    ret = @kn_ccall(get_number_GA_evals, Cint, (Ptr{Cvoid}, Ptr{Cint}),
                    m.env, fc_eval)
    _checkraise(ret)
    return fc_eval[1]
end

function KN_get_number_H_evals(m::Model)
    fc_eval = Int32[0]
    ret = @kn_ccall(get_number_H_evals, Cint, (Ptr{Cvoid}, Ptr{Cint}),
                    m.env, fc_eval)
    _checkraise(ret)
    return fc_eval[1]
end

function KN_get_number_HV_evals(m::Model)
    fc_eval = Int32[0]
    ret = @kn_ccall(get_number_HV_evals, Cint, (Ptr{Cvoid}, Ptr{Cint}),
                    m.env, fc_eval)
    _checkraise(ret)
    return fc_eval[1]
end

##################################################
# Residual callbacks
##################################################
function eval_rsd_wrapper(ptr_model::Ptr{Cvoid}, ptr_cb::Ptr{Cvoid},
                          evalRequest_::Ptr{Cvoid},
                          evalResults_::Ptr{Cvoid},
                          userdata_::Ptr{Cvoid})

    # load evalRequest object
    ptr0 = Ptr{KN_eval_request}(evalRequest_)
    evalRequest = unsafe_load(ptr0)::KN_eval_request

    # load evalResult object
    ptr = Ptr{KN_eval_result}(evalResults_)
    evalResult = unsafe_load(ptr)::KN_eval_result

    # and eventually, load callback context
    cb = unsafe_pointer_to_objref(userdata_)
    # we have to ensure that cb is a CallbackContext
    # otherwise, we tell KNITRO that a problem occurs by returning a
    # non-zero status
    if !isa(cb, CallbackContext)
        return Cint(32)
    end

    request = EvalRequest(cb.model, evalRequest)
    result = EvalResult(cb.model, ptr_cb, evalResult)

    cb.eval_rsd(ptr_model, ptr_cb, request, result, cb.userparams)

    return Cint(0)
end

# TODO: add _one and _* support
"""
    KN_add_lsq_eval_callback(m::Model, rsdCallBack::Function)

Add an evaluation callback for a least-squares models.  Similar to KN_add_eval_callback()
above, but for least-squares models.

* `m`: current KNITRO model
* `rsdCallback`: a function that evaluates any residual parts

After a callback is created by `KN_add_lsq_eval_callback()`, the user can then
specify residual Jacobian information and structure through `KN_set_cb_rsd_jac()`.
If not set, Knitro will approximate the residual Jacobian.  However, it is highly
recommended to provide a callback routine to specify the residual Jacobian if at all
possible as this will greatly improve the performance of Knitro.  Even if a callback
for the residual Jacobian is not provided, it is still helpful to provide the sparse
Jacobian structure for the residuals through `KN_set_cb_rsd_jac()` to improve the
efficiency of the finite-difference Jacobian approximation.

"""
function KN_add_lsq_eval_callback(m::Model, rsdCallBack::Function)

    # wrap eval_callback_wrapper as C function
    c_f = @cfunction(eval_rsd_wrapper, Cint,
                   (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))

    # define callback context
    rfptr = Ref{Ptr{Cvoid}}()

    # add callback to context
    ret = @kn_ccall(add_lsq_eval_callback_all, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                    m.env, c_f, rfptr)
    _checkraise(ret)
    cb = CallbackContext(rfptr.x, m)

    # store function inside model:
    cb.eval_rsd = rsdCallBack

    KN_set_cb_user_params(m, cb)

    return cb
end

function eval_rj_wrapper(ptr_model::Ptr{Cvoid}, ptr_cb::Ptr{Cvoid},
                         evalRequest_::Ptr{Cvoid},
                         evalResults_::Ptr{Cvoid},
                         userdata_::Ptr{Cvoid})

    # load evalRequest object
    ptr0 = Ptr{KN_eval_request}(evalRequest_)
    evalRequest = unsafe_load(ptr0)::KN_eval_request

    # load evalResult object
    ptr = Ptr{KN_eval_result}(evalResults_)
    evalResult = unsafe_load(ptr)::KN_eval_result

    # and eventually, load callback context
    cb = unsafe_pointer_to_objref(userdata_)
    # we have to ensure that cb is a CallbackContext
    # otherwise, we tell KNITRO that a problem occurs by returning a
    # non-zero status
    if !isa(cb, CallbackContext)
        return Cint(32)
    end

    request = EvalRequest(cb.model, evalRequest)
    result = EvalResult(cb.model, ptr_cb, evalResult)

    cb.eval_jac_rsd(ptr_model, ptr_cb, request, result, cb.userparams)

    return Cint(0)
end

function KN_set_cb_rsd_jac(m::Model, cb::CallbackContext, nnzJ::Integer, evalRJ::Function;
                           jacIndexRsds=C_NULL, jacIndexVars=C_NULL)
    # check consistency of arguments
    if nnzJ == KN_DENSE_ROWMAJOR || nnzJ == KN_DENSE_COLMAJOR || nnzJ == 0
        @assert jacIndexRsds == jacIndexVars == C_NULL
    else
        @assert jacIndexRsds != C_NULL && jacIndexVars != C_NULL
        @assert length(jacIndexRsds) == length(jacIndexVars) == nnzJ
    end

    # store function inside model:
    cb.eval_jac_rsd = evalRJ
    # wrap as C function
    c_eval_rj = @cfunction(eval_rj_wrapper, Cint,
                           (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))
    ret = @kn_ccall(set_cb_rsd_jac, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, KNLONG, Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}),
                    m.env, cb.context, nnzJ,
                    jacIndexRsds, jacIndexVars, c_eval_rj)

    _checkraise(ret)

    return cb
end


##################################################
# User callbacks wrapper
##################################################
#--------------------
# New estimate callback
#--------------------
function newpt_wrapper(ptr_model::Ptr{Cvoid},
                       ptr_x::Ptr{Cdouble},
                       ptr_lambda::Ptr{Cdouble},
                       userdata_::Ptr{Cvoid})

    # Load KNITRO's Julia Model
    m = unsafe_pointer_to_objref(userdata_)::Model
    nx = KN_get_number_vars(m)
    nc = KN_get_number_cons(m)

    x = unsafe_wrap(Array, ptr_x, nx)
    lambda = unsafe_wrap(Array, ptr_lambda, nx + nc)
    m.user_callback(ptr_model, x, lambda, m)

    return Cint(0)
end

"""
    KN_set_newpt_callback(m::Model, callback::Function)

Set the callback function that is invoked after Knitro computes a
new estimate of the solution point (i.e., after every iteration).
The function should not modify any Knitro arguments.

Callback is a function with signature:

    callback(kc, x, lambda, userdata)

Argument `kc` passed to the callback from inside Knitro is the
context pointer for the current problem being solved inside Knitro
(either the main single-solve problem, or a subproblem when using
multi-start, Tuner, etc.).
Arguments `x` and `lambda` contain the latest solution estimates.
Other values (such as objective, constraint, jacobian, etc.) can be
queried using the corresonding KN_get_XXX_values methods.

Note: Currently only active for continuous models.

"""
function KN_set_newpt_callback(m::Model, callback::Function)
    # store callback function inside model:
    m.user_callback = callback

    # wrap user callback wrapper as C function
    c_func = @cfunction(newpt_wrapper, Cint,
                        (Ptr{Cvoid}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cvoid}))

    ret = @kn_ccall(set_newpt_callback, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, c_func, m)
    _checkraise(ret)

    return nothing
end

#--------------------
# Multistart callback
#--------------------
function ms_process_wrapper(ptr_model::Ptr{Cvoid},
                            ptr_x::Ptr{Cdouble},
                            ptr_lambda::Ptr{Cdouble},
                            userdata_::Ptr{Cvoid})

    # Load KNITRO's Julia Model
    m = unsafe_pointer_to_objref(userdata_)::Model
    nx = KN_get_number_vars(m)
    nc = KN_get_number_cons(m)

    x = unsafe_wrap(Array, ptr_x, nx)
    lambda = unsafe_wrap(Array, ptr_lambda, nx + nc)
    m.ms_process(ptr_model, x, lambda, m)

    return Cint(0)
end

"""
    KN_set_ms_process_callback(m::Model, callback::Function)

This callback function is for multistart (MS) problems only.
Set the callback function that is invoked after Knitro finishes
processing a multistart solve.

Callback is a function with signature:

    callback(kc, x, lambda, userdata)

Argument `kc` passed to the callback
from inside Knitro is the context pointer for the last multistart
subproblem solved inside Knitro.  The function should not modify any
Knitro arguments.  Arguments `x` and `lambda` contain the solution from
the last solve.

"""
function KN_set_ms_process_callback(m::Model, callback::Function)
    # store callback function inside model:
    m.ms_process = callback

    # wrap user callback wrapper as C function
    c_func = @cfunction(ms_process_wrapper, Cint,
                        (Ptr{Cvoid}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cvoid}))

    ret = @kn_ccall(set_ms_process_callback, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, c_func, m)
    _checkraise(ret)
end

#--------------------
# MIP callback
#--------------------
function mip_node_callback_wrapper(ptr_model::Ptr{Cvoid},
                                   ptr_x::Ptr{Cdouble},
                                   ptr_lambda::Ptr{Cdouble},
                                   userdata_::Ptr{Cvoid})

    # Load KNITRO's Julia Model
    m = unsafe_pointer_to_objref(userdata_)::Model
    nx = KN_get_number_vars(m)
    nc = KN_get_number_cons(m)

    x = unsafe_wrap(Array, ptr_x, nx)
    lambda = unsafe_wrap(Array, ptr_lambda, nx + nc)
    m.mip_callback(ptr_model, x, lambda, m)

    return Cint(0)
end

"""
    KN_set_mip_node_callback(m::Model, callback::Function)

This callback function is for mixed integer (MIP) problems only.
Set the callback function that is invoked after Knitro finishes
processing a node on the branch-and-bound tree (i.e., after a relaxed
subproblem solve in the branch-and-bound procedure).

Callback is a function with signature:

    callback(kc, x, lambda, userdata)

Argument `kc` passed to the callback from inside Knitro is the
context pointer for the last node subproblem solved inside Knitro.
The function should not modify any Knitro arguments.
Arguments `x` and `lambda` contain the solution from the node solve.

"""
function KN_set_mip_node_callback(m::Model, callback::Function)
    # store callback function inside model:
    m.mip_callback = callback

    # wrap user callback wrapper as C function
    c_func = @cfunction(mip_node_callback_wrapper, Cint,
                        (Ptr{Cvoid}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cvoid}))

    ret = @kn_ccall(set_mip_node_callback, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, c_func, m)
    _checkraise(ret)
end

#--------------------
# Multistart procedure callback
#--------------------
function ms_initpt_wrapper(ptr_model::Ptr{Cvoid},
                           nSolveNumber::Cint,
                           ptr_x::Ptr{Cdouble},
                           ptr_lambda::Ptr{Cdouble},
                           userdata_::Ptr{Cvoid})

    # Load KNITRO's Julia Model
    m = unsafe_pointer_to_objref(userdata_)::Model
    nx = KN_get_number_vars(m)
    nc = KN_get_number_cons(m)

    x = unsafe_wrap(Array, ptr_x, nx)
    lambda = unsafe_wrap(Array, ptr_lambda, nx + nc)
    m.ms_initpt_callback(ptr_model, nSolveNumber, x, lambda, m)

    return Cint(0)
end

"""
    KN_set_ms_initpt_callback(m::Model, callback::Function)
Type declaration for the callback that allows applications to
specify an initial point before each local solve in the multistart
procedure.

Callback is a function with signature:

    callback(kc, x, lambda, userdata)

On input, arguments `x` and `lambda` are the randomly
generated initial points determined by Knitro, which can be overwritten
by the user.  The argument `nSolveNumber` is the number of the
multistart solve.

"""
function KN_set_ms_initpt_callback(m::Model, callback::Function)
    # store callback function inside model:
    m.ms_initpt_callback = callback

    # wrap user callback wrapper as C function
    c_func = @cfunction(ms_initpt_wrapper, Cint,
                        (Ptr{Cvoid}, Cint, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cvoid}))

    ret = @kn_ccall(set_ms_initpt_callback, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, c_func, m)
    _checkraise(ret)
end

#--------------------
# Puts callback
#--------------------
function puts_callback_wrapper(str::Ptr{Cchar}, userdata_::Ptr{Cvoid})

    # Load KNITRO's Julia Model
    m = unsafe_pointer_to_objref(userdata_)::Model
    res = m.puts_callback(unsafe_string(str), m.userdata)

    return Cint(res)
end

"""
    KN_set_puts_callback(m::Model, callback::Function)

Set the callback that allows applications to handle
output. Applications can set a `put string` callback function to handle
output generated by the Knitro solver.  By default Knitro prints to
stdout or a file named `knitro.log`, as determined by KN_PARAM_OUTMODE.

Callback is a function with signature:

    callback(str::String, userdata)

The KN_puts callback function takes a `userParams` argument which is a pointer
passed directly from KN_solve. The function should return the number of
characters that were printed.

"""
function KN_set_puts_callback(m::Model, callback::Function)
    # store callback function inside model:
    m.puts_callback = callback

    # wrap user callback wrapper as C function
    c_func = @cfunction(puts_callback_wrapper, Cint,
                        (Ptr{Cchar}, Ptr{Cvoid}))

    ret = @kn_ccall(set_puts_callback, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Any),
                    m.env, c_func, m)
end
