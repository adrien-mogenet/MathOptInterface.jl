"""
    SlackBridge{T, F, G}

The `SlackBridge` converts an objective function of type `G` into a
[`SingleVariable`](@ref) objective by creating a slack variable and a
`F`-in-[`LessThan`](@ref) constraint for minimization or
`F`-in-[`LessThan`](@ref) constraint for maximization where `F` is
`MOI.Utilities.promote_operation(-, T, G, MOI.SingleVariable}`.
Note that when using this bridge, changing the optimization sense
is not supported. Set the sense to `MOI.FEASIBILITY_SENSE` first
to delete the bridge in order to change the sense, then re-add the objective.
"""
struct SlackBridge{T, F<:MOI.AbstractScalarFunction, G<:MOI.AbstractScalarFunction} <: AbstractBridge
    slack::MOI.VariableIndex
    constraint::Union{MOI.ConstraintIndex{F, MOI.LessThan{T}},
                      MOI.ConstraintIndex{F, MOI.GreaterThan{T}}}
end
function bridge_objective(::Type{SlackBridge{T, F, G}}, model::MOI.ModelLike,
                          func::G) where {T, F, G<:MOI.AbstractScalarFunction}
    slack = MOI.add_variable(model)
    fslack = MOI.SingleVariable(slack)
    f = MOIU.operate(-, T, func, fslack)
    if MOI.get(model, MOI.ObjectiveSense()) == MOI.MIN_SENSE
        set = MOI.LessThan(zero(T))
    elseif MOI.get(model, MOI.ObjectiveSense()) == MOI.MAX_SENSE
        set = MOI.GreaterThan(zero(T))
    else
        error("Set `MOI.ObjectiveSense` before `MOI.ObjectiveFunction` when",
              " using `MOI.Bridges.Objective.SlackBridge`.")
    end
    constraint = MOIU.add_scalar_constraint(model, f, set)
    MOI.set(model, MOI.ObjectiveFunction{MOI.SingleVariable}(), fslack)
    return SlackBridge{T, F, G}(slack, constraint)
end

function supports_objective_function(
    ::Type{<:SlackBridge}, ::Type{MOI.SingleVariable})
    return false
end
function supports_objective_function(
    ::Type{<:SlackBridge}, ::Type{<:MOI.AbstractScalarFunction})
    return true
end
MOIB.added_constrained_variable_types(::Type{<:SlackBridge}) = Tuple{DataType}[]
function MOIB.added_constraint_types(::Type{<:SlackBridge{T, F}}) where {T, F}
    return [(F, MOI.GreaterThan{T}), (F, MOI.LessThan{T})]
end
function MOIB.set_objective_function_type(::Type{<:SlackBridge})
    return MOI.SingleVariable
end
function concrete_bridge_type(::Type{<:SlackBridge{T}},
                              G::Type{<:MOI.AbstractScalarFunction}) where T
    F = MOIU.promote_operation(-, T, G, MOI.SingleVariable)
    return SlackBridge{T, F, G}
end


function MOI.delete(model::MOI.ModelLike, bridge::SlackBridge)
    MOI.delete(model, bridge.constraint)
    MOI.delete(model, bridge.slack)
end

function MOI.get(model::MOI.ModelLike,
                 attr::MOIB.ObjectiveFunctionValue{G},
                 bridge::SlackBridge{T, F, G}) where {T, F, G}
    slack = MOI.get(model, MOIB.ObjectiveFunctionValue{MOI.SingleVariable}())
    obj_slack_constant = MOI.get(model, MOI.ConstraintPrimal(), bridge.constraint)
    # The constant was moved to the set as it is a scalar constraint.
    constant = MOI.constant(MOI.get(model, MOI.ConstraintSet(), bridge.constraint))
    return obj_slack_constant + slack + constant
end
function MOI.get(model::MOI.ModelLike, attr::MOI.ObjectiveFunction{MOI.SingleVariable},
                 bridge::SlackBridge{T}) where T
    func = MOI.get(model, MOI.ObjectiveFunction{MOI.SingleVariable}())
    return MOIU.remove_variable(func, bridge.slack)
end
