#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if it doesn't exist
mkdir -p results

# Reference indexing (once)
ref_fa=data/ref/chrM.fa
faidx=${ref_fa}.fai
bwa_idx=${ref_fa}.bwt
if [[ ! -f "$faidx" || ! -f "$bwa_idx" ]]; then
    samtools faidx "$ref_fa"
    bwa index "$ref_fa"
fi

# Per-sample processing
for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    bai=${bam}.bai
    vcf=results/${sample}.vcf
    vcf_gz=${vcf}.gz
    tbi=${vcf_gz}.tbi

    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz

    # Skip if final VCF index exists and is newer than inputs
    if [[ ! -e "$tbi" || $tbi -ot "$fq1" || $tbi -ot "$fq2" || $tbi -ot "$ref_fa" ]]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
        samtools index -@ "$THREADS" "$bam"
        lofreq call-parallel --pp-threads "$THREADS" -f "$ref_fa" -o "$vcf" "$bam"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm "$vcf"
    fi
done

# Build collapsed.tsv
tsv=results/collapsed.tsv
needs_rebuild=false
if [[ ! -e "$tsv" ]]; then
    needs_rebuild=true
else
    for sample in "${samples[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        if [[ $vcf_gz -ot "$tsv" ]]; then
            needs_rebuild=true
            break
        fi
    done
fi

if $needs_rebuild; then
    tmp=results/collapsed.tsv.tmp
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmp"
    for sample in "${samples[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> "$tmp"
    done
    mv "$tmp" "$tsv"
fi

exit 0