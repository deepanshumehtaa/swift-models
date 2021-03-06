// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import TensorFlow

/// Adam optimizer with weight decay.
///
/// Reference: ["Adam - A Method for Stochastic Optimization"](
/// https://arxiv.org/abs/1412.6980v8)
public struct WeightDecayedAdam<Model: Regularizable, LearningRate: ScheduledParameter>: Optimizer
where
    Model.TangentVector: VectorProtocol & PointwiseMultiplicative & ElementaryFunctions
        & KeyPathIterable,
    Model.TangentVector.VectorSpaceScalar == Float,
    LearningRate.Scalar == Float
{
    /// The learning rate to use when updating models.
    public var scheduledLearningRate: LearningRate

    public var learningRate: Float

    /// The weight decay rate.
    public var weightDecayRate: Float

    /// An indicator for whether or not to use bias correction.
    public var useBiasCorrection: Bool

    /// A coefficient used to calculate the first and second moments of the gradients.
    public var beta1: Float

    /// A coefficient used to calculate the first and second moments of the gradients.
    public var beta2: Float

    /// A small scalar added to the denominator to improve numerical stability.
    public var epsilon: Float

    /// The maximum allowed gradient global norm. If the gradients global norm is larger than this
    /// value, then the gradients will be clipped to satisfy this constraint.
    public var maxGradientGlobalNorm: Float?

    /// The current step.
    public var step: UInt64 = 0 {
        didSet {
            if useBiasCorrection {
                let step = Float(self.step)
                learningRate *= sqrtf(1 - powf(beta2, step)) / (1 - powf(beta1, step))
            } else {
                learningRate = scheduledLearningRate(forStep: step)
            }
        }
    }

    /// The first moments of the weights.
    public var firstMoments: Model.TangentVector = .zero

    /// The second moments of the weights.
    public var secondMoments: Model.TangentVector = .zero

    public init(
        for model: __shared Model,
        scheduledLearningRate: LearningRate,
        weightDecayRate: Float = 0.01,
        useBiasCorrection: Bool = true,
        beta1: Float = 0.9,
        beta2: Float = 0.999,
        epsilon: Float = 1e-6,
        maxGradientGlobalNorm: Float? = nil
    ) {
        precondition(0 <= beta1 && beta1 <= 1, "Beta parameter must be between 0 and 1")
        precondition(0 <= beta2 && beta2 <= 1, "Beta parameter must be between 0 and 1")

        self.scheduledLearningRate = scheduledLearningRate
        self.learningRate = self.scheduledLearningRate(forStep: step)
        self.weightDecayRate = weightDecayRate
        self.useBiasCorrection = useBiasCorrection
        self.beta1 = beta1
        self.beta2 = beta2
        self.epsilon = epsilon
        self.maxGradientGlobalNorm = maxGradientGlobalNorm
    }

    public init(copying other: WeightDecayedAdam, to device: Device) {
        self.scheduledLearningRate = other.scheduledLearningRate
        self.learningRate = other.learningRate
        self.weightDecayRate = other.weightDecayRate
        self.useBiasCorrection = other.useBiasCorrection
        self.beta1 = other.beta1
        self.beta2 = other.beta2
        self.epsilon = other.epsilon
        self.maxGradientGlobalNorm = other.maxGradientGlobalNorm
        self.firstMoments = .init(copying: other.firstMoments, to: device)
        self.secondMoments = .init(copying: other.secondMoments, to: device)
    }

    public mutating func update(_ model: inout Model, along direction: Model.TangentVector) {
        var direction = direction
        if let globalNorm = maxGradientGlobalNorm {
            direction.clipByGlobalNorm(clipNorm: globalNorm)
        }
        step += 1
        firstMoments = firstMoments.scaled(by: beta1)
        firstMoments += direction.scaled(by: 1 - beta1)
        secondMoments = secondMoments.scaled(by: beta2)
        secondMoments += direction .* direction.scaled(by: 1 - beta2)
        let denominator = Model.TangentVector.sqrt(secondMoments).adding(epsilon)
        let weightDecay = model.regularizationValue.scaled(by: weightDecayRate)
        let update = firstMoments ./ denominator + weightDecay
        model.move(along: update.scaled(by: -learningRate))
    }
}
