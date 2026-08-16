#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}
REF="data/ref/chrM.fa"
RAWDIR="data/raw"
OUTDIR="results"

mkdir -p "$OUTDIR"

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
    bam="${OUTDIR}/${sample}.bam"
    bai="${OUTDIR}/${sample}.bam.bai"
    vcf="${OUTDIR}/${sample}.vcf.gz"
    tbi="${OUTDIR}/${sample}.vcf.gz.tbi"

    [[ -f "$tbi" ]] && continue

    if [[ ! -f "$bai" ]]; then
        bwa mem -t "$THREADS" "$REF" \
            "${RAWDIR}/${sample}_1.fq.gz" \
            "${RAWDIR}/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$bam"
        samtools index "$bam"
    fi

    if [[ ! -f "$tbi" ]]; then
        bcftools mpileup -f "$REF" -Ov "$bam" | \
            bcftools call -mv -Oz -o "${vcf}.tmp"

        bcftools norm -m -any -Oz "${vcf}.tmp" -o "$vcf"
        rm -f "${vcf}.tmp"

        tabix -p vcf "$vcf"
    fi
done

{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${SAMPLES[@]}"; do
        vcf="${OUTDIR}/${sample}.vcf.gz"
        [[ -f "$vcf" ]] || continue
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" | \
            awk -v s="$sample" '{print s"\t"$0}'
    done
} > "${OUTDIR}/collapsed.tsv"