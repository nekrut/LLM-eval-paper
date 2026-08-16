#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# 1. Reference indexing — BWA
[[ -f "${REF}.bwt" ]] || bwa index "$REF"

# 2. Reference indexing — samtools faidx
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for sample in "${SAMPLES[@]}"; do
    # 3. Alignment + coordinate sort
    [[ -f "${OUTDIR}/${sample}.bam" ]] || {
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
        | samtools sort -@ "$THREADS" -o "${OUTDIR}/${sample}.bam" -
    }

    # 4. BAM index
    [[ -f "${OUTDIR}/${sample}.bam.bai" ]] || samtools index -@ "$THREADS" "${OUTDIR}/${sample}.bam"

    # 5. Variant calling — LoFreq
    [[ -f "${OUTDIR}/${sample}.vcf" || -f "${OUTDIR}/${sample}.vcf.gz" ]] || \
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${OUTDIR}/${sample}.vcf" "${OUTDIR}/${sample}.bam"

    # 6. Compress + tabix index
    [[ -f "${OUTDIR}/${sample}.vcf.gz.tbi" ]] || {
        bgzip -f "${OUTDIR}/${sample}.vcf"
        tabix -p vcf "${OUTDIR}/${sample}.vcf.gz"
    }
done

# 7. Collapsed table (rebuilt every run)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${OUTDIR}/collapsed.tsv"
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${OUTDIR}/${sample}.vcf.gz" \
    | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "${OUTDIR}/collapsed.tsv"
done